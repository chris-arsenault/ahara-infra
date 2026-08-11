output "role_arn" {
  value = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "deployment_revision" {
  description = "Hash of the effective deployer policy after its policies and attachments are ready"
  value       = sha256(jsonencode(local.all_statements))

  depends_on = [
    aws_iam_policy.bundles,
    aws_iam_role_policy_attachment.bundles,
  ]
}
