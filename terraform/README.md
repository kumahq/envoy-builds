# Using terraform to build Envoy

## Github Action

AWS has a limit of VPCs and to not hit this issue we are reusing VPC that is predefined in the cloud. You can recreate it by entering
`./vpc` and running `terraform plan` and `terraform apply`.
