output "cognito_user_pool_id" {
  description = "Cognito user pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_client_ids" {
  description = "Map of app keys to Cognito client IDs"
  value       = module.cognito.client_ids
}

output "cognito_chris_password" {
  description = "Initial password for seed admin user"
  value       = random_password.cognito_chris.result
  sensitive   = true
}

output "alarm_topic_arn" {
  description = "SNS topic ARN for shared-infra alarms"
  value       = aws_sns_topic.alarms.arn
}

output "rum_identity_pool_id" {
  description = "Shared Cognito identity pool ID for browser CloudWatch RUM clients"
  value       = aws_cognito_identity_pool.rum.id
}

output "rum_guest_role_arn" {
  description = "Shared unauthenticated role ARN for browser CloudWatch RUM clients"
  value       = aws_iam_role.rum_unauthenticated.arn
}

output "rds_endpoint" {
  description = "Shared RDS endpoint"
  value       = aws_db_instance.ahara.endpoint
}
