
locals {
  deployment_role_name = "deployer-${var.prefix}"
  project_boundary_arn = "arn:aws:iam::${var.account_id}:policy/pb-${var.prefix}-project-guardrails"
  # Common ARNs
  prefixed_roles_arn       = "arn:aws:iam::${var.account_id}:role/deployer-*"
  permissions_boundary_arn = "arn:aws:iam::${var.account_id}:policy/pb-*"
}