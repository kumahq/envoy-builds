locals {
  linux_user_data = <<EOF
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

usermod -a -G docker admin

touch /home/admin/ready
EOF
}

data "aws_ssm_parameter" "debian" {
  name = "/aws/service/debian/release/12/latest/${var.arch}"
}
