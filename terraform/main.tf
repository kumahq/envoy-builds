terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.67.0"
    }
  }
}

variable "public_key_path" {
  type        = string
  description = "Path to public key for creating a key pair"
}

variable "arch" {
  type        = string
  description = "amd64 or arm64"
  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "amd64 or arm64"
  }
}

variable "fips" {
  description = "fips build"
  type        = bool
}

variable "envoy_version" {
  type        = string
  description = "Envoy version, not prefixed with v"
  default     = "main"
}

locals {
  instance_type = {
    amd64 = "c6i.4xlarge"
    arm64 = "c7g.4xlarge"
  }
  name_suffix = "${var.arch}-${var.envoy_version}${var.fips ? "-fips" : ""}"
}

provider "aws" {
  region = "us-east-2"
}

data "aws_vpc" "exisiting_vpc" {
  filter {
    name   = "tag:Name"
    values = ["envoy-ci"]
  }
}

data "aws_subnet" "exisiting_subnet" {
  vpc_id            = data.aws_vpc.exisiting_vpc.id
  availability_zone = "us-east-2b"
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws//modules/ssh"
  version = "4.17.1"

  name   = "envoy-ci-ssh"
  vpc_id = data.aws_vpc.exisiting_vpc.id

  ingress_cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_key_pair" "ci" {
  key_name   = "envoy-ci-linux-${local.name_suffix}"
  public_key = trimspace(file(var.public_key_path))
}

resource "aws_instance" "envoy-ci-build" {
  ami = data.aws_ssm_parameter.debian.value

  instance_type = local.instance_type[var.arch]

  iam_instance_profile = aws_iam_instance_profile.envoy-ci-build.name

  key_name = aws_key_pair.ci.id

  tags = {
    Name = "envoy-ci-linux-${local.name_suffix}"
  }

  root_block_device {
    # bazel's output tree plus the buildkit cache outgrew 100GB on linux/amd64
    volume_size = "200"
  }

  subnet_id              = data.aws_subnet.exisiting_subnet.id
  vpc_security_group_ids = [module.security_group.security_group_id]

  user_data = local.linux_user_data

  user_data_replace_on_change = true
}

resource "aws_iam_instance_profile" "envoy-ci-build" {
  role = aws_iam_role.role.name

  name = "envoy-ci-build-linux-${local.name_suffix}"
}

resource "aws_iam_role" "role" {
  name = "envoy-ci-build-linux-${local.name_suffix}"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF

  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", "arn:aws:iam::aws:policy/AmazonS3FullAccess"]
}

output "public_ip" {
  value = aws_instance.envoy-ci-build.public_ip
}

output "instance_id" {
  value = aws_instance.envoy-ci-build.id
}
