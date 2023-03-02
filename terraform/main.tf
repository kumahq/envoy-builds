variable "public_key_path" {
  type = string
  description = "Path to public key for creating a key pair"
}

variable "arch" {
  type = string
  description = "amd64 or arm64"
  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "amd64 or arm64"
  }
}

variable "os" {
  type = string
  description = "linux or darwin"
  validation {
    condition     = contains(["linux", "darwin"], var.os)
    error_message = "linux or darwin"
  }
}

provider "aws" {
  region = "us-east-2"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "envoy-ci"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2b"]
  private_subnets = []
  public_subnets  = ["10.0.101.0/24"]
}

module "security_group" {
  source = "terraform-aws-modules/security-group/aws//modules/ssh"

  name        = "envoy-ci-ssh"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_key_pair" "ci" {
  key_name = "envoy-ci"
  public_key = trimspace(file(var.public_key_path))
}

resource "aws_instance" "envoy-ci-build" {
  ami           = var.os == "linux" ? data.aws_ssm_parameter.debian.value : data.aws_ami.mac.image_id

  instance_type = (var.os == "linux"
    ? (var.arch == "amd64" ? "t3.2xlarge" : "t4g.2xlarge")
    : (var.arch == "amd64" ? "mac1.metal" : "mac2.metal")
  )

  iam_instance_profile = aws_iam_instance_profile.envoy-ci-build.name

  key_name = aws_key_pair.ci.id

  tags = {
    Name = "envoy-ci"
  }

  root_block_device {
    volume_size = "100"
  }

  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [module.security_group.security_group_id]

  user_data = var.os == "linux" ? local.linux_user_data : local.macos_user_data

  host_id = var.os == "darwin" ? var.host_id : ""

  user_data_replace_on_change = true
}

resource "aws_iam_instance_profile" "envoy-ci-build" {
  role = aws_iam_role.role.name

  name        = "envoy-ci-build"
}

resource "aws_iam_role" "role" {
  name = "envoy-ci-build"
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

  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
}

output "public_ip" {
  value = aws_instance.envoy-ci-build.public_ip
}
