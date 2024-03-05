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

variable "os" {
  type        = string
  description = "linux or darwin or windows"
  validation {
    condition     = contains(["linux", "darwin", "windows"], var.os)
    error_message = "linux or darwin or windows"
  }
}

variable "fips" {
  description = "fips build"
  type   = bool
}

variable "envoy_version" {
  type        = string
  description = "Envoy version"
  default     = "1.28"
}

locals {
  ami = {
    linux = data.aws_ssm_parameter.debian.value
    darwin = data.aws_ami.mac.image_id
    windows = data.aws_ssm_parameter.windows.value
  }
  instance_type = {
    darwin = {
      amd64 = "mac1.metal"
      arm64 = "mac2.metal"
    }
    linux = {
      amd64 = "c6i.4xlarge"
      arm64 = "c7g.4xlarge"
    }
    windows = {
      amd64 = "c6i.4xlarge"
    }
  }
  user_data = {
    linux = local.linux_user_data
    darwin = local.macos_user_data
    windows = local.windows_user_data
  }
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
  source = "terraform-aws-modules/security-group/aws//modules/ssh"
  version = "4.17.1"

  name   = "envoy-ci-ssh"
  vpc_id = data.aws_vpc.exisiting_vpc.id

  ingress_cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_key_pair" "ci" {
  key_name = "envoy-ci-${var.os}-${var.arch}-${var.envoy_version}${var.fips ? "-fips" : ""}"
  public_key = trimspace(file(var.public_key_path))
}

resource "aws_instance" "envoy-ci-build" {
  ami = local.ami[var.os]

  instance_type = local.instance_type[var.os][var.arch]

  iam_instance_profile = aws_iam_instance_profile.envoy-ci-build.name

  key_name = aws_key_pair.ci.id

  tags = {
    Name = "envoy-ci-${var.os}-${var.arch}-${var.envoy_version}${var.fips ? "-fips" : ""}"
  }

  root_block_device {
    volume_size = "100"
  }

  subnet_id = data.aws_subnet.exisiting_subnet.id
  vpc_security_group_ids = [module.security_group.security_group_id]

  user_data = local.user_data[var.os]

  host_id = var.os == "darwin" ? var.host_id : ""

  user_data_replace_on_change = true
}

resource "aws_iam_instance_profile" "envoy-ci-build" {
  role = aws_iam_role.role.name

  name = "envoy-ci-build-${var.os}-${var.arch}-${var.envoy_version}${var.fips ? "-fips" : ""}"
}

resource "aws_iam_role" "role" {
  name = "envoy-ci-build-${var.os}-${var.arch}-${var.envoy_version}${var.fips ? "-fips" : ""}"
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

  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore","arn:aws:iam::aws:policy/AmazonS3FullAccess"]
}

output "public_ip" {
  value = aws_instance.envoy-ci-build.public_ip
}

output "instance_id" {
  value = aws_instance.envoy-ci-build.id
}
