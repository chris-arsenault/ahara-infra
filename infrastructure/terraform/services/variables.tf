variable "domain_name" {
  description = "Primary domain for shared services"
  type        = string
  default     = "ahara.io"
}

variable "cognito_user_pool_name" {
  description = "Override for the shared Cognito user pool name (defaults to <prefix>-users)"
  type        = string
  default     = null
}

variable "cognito_clients" {
  description = "Map of app keys to Cognito client display names (empty falls back to <prefix>-canonry-app plus svap-app)"
  type        = map(string)
  default     = {}
}

variable "seed_user_email" {
  description = "Email for the seed admin user"
  type        = string
  default     = "chris@chris-arsenault.net"
}

# =============================================================================
# Inputs from the network module (wired in root main.tf)
# =============================================================================

variable "vpc_id" {
  description = "VPC id from the network module"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet ids from the network module"
  type        = list(string)
}

variable "alb_listener_arn" {
  description = "Shared ALB HTTPS listener ARN from the network module"
  type        = string
}

variable "alb_dns_name" {
  description = "Shared ALB DNS name from the network module (for Route53 alias records)"
  type        = string
}

variable "alb_zone_id" {
  description = "Shared ALB Route53 zone id from the network module (for Route53 alias records)"
  type        = string
}

variable "alb_sg_id" {
  description = "Shared ALB security group id from the network module"
  type        = string
}

variable "ahara_lambda_sg_id" {
  description = "Shared VPC Lambda security group id from the network module"
  type        = string
}

variable "vpn_client_sg_id" {
  description = "VPN client security group id from the network module (opt-in for Lambdas that need TrueNAS/WireGuard access)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 zone id for ahara.io from the network module"
  type        = string
}

variable "reverse_proxy_target_group_arn" {
  description = "Reverse proxy ALB target group ARN from the network module"
  type        = string
}

variable "reverse_proxy_cognito_hosts" {
  description = "List of hostnames that should be gated by Cognito authentication on the shared ALB"
  type        = list(string)
}
