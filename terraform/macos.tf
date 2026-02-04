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

sudo -u ec2-user -i <<'SUDOEOF'
trap 'touch ~/ready' EXIT
echo "alias python=python3" >> ~/.bash_profile
brew install llvm@18 && ln -sf "$(brew --prefix llvm@18)/bin/llvm-libtool-darwin" "$(brew --prefix llvm@18)/bin/libtool"
brew install bash automake cmake coreutils libtool wget ninja go bazelisk
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
