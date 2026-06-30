output "role_arn" {
  value = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "workload_id" {
  value = local.workload_id
}

output "role_arn_parameter" {
  value = aws_ssm_parameter.role_arn.name
}
