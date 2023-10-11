data "aws_ssm_parameter" "windows" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Core-ECS_Optimized/image_id"
}
