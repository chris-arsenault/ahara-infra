output "policy_json" {
  description = "ARN of the policy to allow deployments to do with IAM"
  value       = data.aws_iam_policy_document.this.json
}