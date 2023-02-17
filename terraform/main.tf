variable "public_key_path" {
  type = string
  description = "Path to public key for creating a key pair"
}

provider "aws" {
  region = "us-east-2"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "build-envoy"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2a"]
  private_subnets = []
  public_subnets  = ["10.0.101.0/24"]
}

data "aws_ssm_parameter" "debian" {
  name = "/aws/service/debian/release/11/latest/amd64"
}

module "security_group" {
  source = "terraform-aws-modules/security-group/aws//modules/ssh"

  name        = "build-envoy-ssh"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_key_pair" "ci" {
  key_name = "envoy-ci"
  public_key = file(var.public_key_path)
}

resource "aws_instance" "build-envoy" {
  ami           = data.aws_ssm_parameter.debian.value
  instance_type = "t3.2xlarge"

  iam_instance_profile = aws_iam_instance_profile.build-envoy.name

  key_name = aws_key_pair.ci.id

  tags = {
    Name = "build-envoy"
  }

  root_block_device {
    volume_size = "50"
  }

  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [module.security_group.security_group_id]

  user_data = <<EOF
#!/bin/bash
set -e

apt-get update
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    make \
    golang \
    gpg \
    python3 \
    python-is-python3

sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
EOF

  user_data_replace_on_change = true
}

resource "aws_iam_instance_profile" "build-envoy" {
  role = aws_iam_role.role.name

  name        = "build-envoy"
}

resource "aws_iam_role" "role" {
  name = "build-envoy"
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
  value = aws_instance.build-envoy.public_ip
}
