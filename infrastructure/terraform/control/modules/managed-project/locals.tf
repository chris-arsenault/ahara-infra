
locals {
  project_guardrails_permissions_boundary_name = "pb-${var.prefix}-project-guardrails"
  project_boundary_arn                         = "arn:aws:iam::${var.account_id}:policy/${local.project_guardrails_permissions_boundary_name}"

  # Common ARNs
  all_roles_arn_prefix = "arn:aws:iam::${var.account_id}:role"
  prefixed_roles_arn   = "arn:aws:iam::${var.account_id}:role/${var.prefix}-*"
  deployer_roles_arn   = "arn:aws:iam::${var.account_id}:role/deployer-*"
  all_policies_arn     = "arn:aws:iam::${var.account_id}:policy/*"
  all_users_arn        = "arn:aws:iam::${var.account_id}:user/*"
  all_groups_arn       = "arn:aws:iam::${var.account_id}:group/*"

  allowed_managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole",
    "arn:aws:iam::aws:policy/ReadOnlyAccess"
  ]

  tags = merge(var.tags, {
    Project = var.prefix
  })
}