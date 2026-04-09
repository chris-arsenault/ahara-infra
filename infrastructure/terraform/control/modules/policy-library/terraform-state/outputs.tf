output "policy_json" {
  value = data.aws_iam_policy_document.this.json
}

output "state_bucket" {
  description = "Name of the shared state bucket"
  value       = local.state_bucket
}
