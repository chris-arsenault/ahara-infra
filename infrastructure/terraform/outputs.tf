# Passthrough outputs from layer modules for convenience from `terraform output`.

output "vpc_id" {
  value = module.network.vpc_id
}

output "alb_dns_name" {
  value = module.network.alb_dns_name
}

output "cognito_user_pool_id" {
  value = module.services.cognito_user_pool_id
}

output "cognito_client_ids" {
  value = module.services.cognito_client_ids
}

output "cognito_chris_password" {
  value     = module.services.cognito_chris_password
  sensitive = true
}

output "rds_endpoint" {
  value = module.services.rds_endpoint
}
