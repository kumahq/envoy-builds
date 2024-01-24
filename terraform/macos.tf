variable "host_id" {
  type = string
  default = ""
  description = "Dedicated host id for building on Darwin"
}

locals {
    macos_user_data = <<EOF
#!/bin/bash
set -e

pip3 install virtualenv

sudo -u ec2-user -i <<SUDOEOF
echo "alias python=python3" >> ~/.bash_profile
# Using && is apparently necessary to ensure touch runs. Do not modify without testing!
brew install automake cmake coreutils libtool wget ninja go && brew reinstall --force bazelisk && touch ~/ready
SUDOEOF
EOF
}

data "aws_ami" "mac" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name = "name"
    values = [
      "amzn-ec2-macos-12.*.*-*-*"
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
