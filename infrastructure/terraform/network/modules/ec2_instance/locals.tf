locals {
  instance_tags = { Name = var.name }
  volume_tags   = { Name = "${var.name}-vol" }
  eni_tags      = { Name = "${var.name}-eni" }
  eip_tags      = { Name = "${var.name}-eip" }
  schedule_name = lower("${var.name}-nightly-refresh")
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}
