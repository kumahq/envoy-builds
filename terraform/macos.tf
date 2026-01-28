variable "host_id" {
  type        = string
  default     = ""
  description = "Dedicated host id for building on Darwin"
}

locals {
  macos_version = (
    startswith(var.envoy_version, "1.32")
    || startswith(var.envoy_version, "1.33")
    || startswith(var.envoy_version, "1.34")
  ) ? 12 : 14
  macos_user_data = <<EOF
#!/bin/bash
set -e

sudo -u ec2-user -i <<SUDOEOF
echo "alias python=python3" >> ~/.bash_profile
# Using && is apparently necessary to ensure touch runs. Do not modify without testing!
brew install bash automake cmake coreutils libtool wget ninja go llvm@18 && brew reinstall --force bazelisk
ln -sf /usr/bin/libtool "$(brew --prefix llvm@18)/bin/libtool"
touch ~/ready
SUDOEOF
EOF
}

data "aws_ami" "mac" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name = "name"
    values = [
      "amzn-ec2-macos-${local.macos_version}.*.*-*-*"
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
