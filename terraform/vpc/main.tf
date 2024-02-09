terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.67.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "3.19.0"

  name = "envoy-ci"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2b"]
  private_subnets = []
  public_subnets  = ["10.0.101.0/24"]
}
