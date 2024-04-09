variable "host_id" {
  type = string
  default = ""
  description = "Dedicated host id for building on Darwin"
}

variable "macos_version" {
  type = number
  default = 12
  description = "If using Darwin, which macos major version to use"
}

locals {
    macos_user_data = <<EOF
#!/bin/bash
set -e

sudo -u ec2-user -i <<SUDOEOF
echo "alias python=python3" >> ~/.bash_profile
# Using && is apparently necessary to ensure touch runs. Do not modify without testing!
brew install bash automake cmake coreutils libtool wget ninja go && brew reinstall --force bazelisk && touch ~/ready
SUDOEOF
EOF
}

data "aws_ami" "mac" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name = "name"
    values = [
      "amzn-ec2-macos-${var.macos_version}.*.*-*-*"
    ]
  }
  filter {
    name = "architecture"
    values = [
      var.arch == "amd64" ? "x86_64_mac" : "arm64_mac"
    ]
  }
  filter {
    name = "owner-alias"
    values = [
      "amazon",
    ]
  }
}
