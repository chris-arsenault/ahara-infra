output "policy_json" {
  description = "IAM policy JSON for project-scoped SQS queues."
  value       = data.aws_iam_policy_document.this.json
}
