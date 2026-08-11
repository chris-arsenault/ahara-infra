# =============================================================================
# ahara-infra deployer role
#
# Single deployer OIDC role for the combined infrastructure repo. Replaces the
# three previous roles (deployer-ahara-control, deployer-ahara, deployer-ahara-network)
# with one role whose policy_modules union covers every scope needed to apply
# IAM + VPC + RDS + Lambda + Cognito + S3 + SSM resources under the "ahara-*"
# name prefix.
# =============================================================================

module "ahara_infra_project" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["ahara-infra"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "ahara"
  state_key_prefix = "ahara"

  # alb-api module is consumed by ci-ingest and other ALB-fronted Lambdas.
  module_bundles = ["alb-api"]

  # Union of policy_modules from the three old project files:
  #   project-ahara-control.tf:  control-plane, terraform-state
  #   project-ahara-services.tf: cognito-pool, cognito-client, dynamodb, rds,
  #                              sns, budgets-costexplorer, ssm-write,
  #                              ec2-security-groups, iam-instance-profiles,
  #                              db-migrate
  #   project-ahara-network.tf:  ec2-vpc-compute, alb-loadbalancer,
  #                              alb-target-group, wafv2, acm-dns,
  #                              cognito-identity-pool, iam-roles,
  #                              secrets-manager
  policy_modules = [
    "control-plane",
    "terraform-state",
    "cognito-pool",
    "cognito-client",
    "cognito-identity-pool",
    "dynamodb",
    "rds",
    "sns",
    "budgets-costexplorer",
    "ssm-write",
    "ec2-security-groups",
    "ec2-vpc-compute",
    "iam-instance-profiles",
    "iam-roles",
    "db-migrate",
    "alb-loadbalancer",
    "alb-target-group",
    "cloudfront-distribution",
    "s3-private-storage",
    "s3-website",
    "wafv2",
    "acm-dns",
    "secrets-manager",
    "security-audit",
  ]
}

# The consolidated platform deployer runs the TrueNAS database provisioner and
# the one-time CI history copy. These are Ahara-only rollout operations, so keep
# their invoke grants off the shared db-migrate policy used by product repos.
resource "aws_iam_role_policy" "ahara_infra_platform_migrations" {
  name = "ahara-platform-migrations"
  role = module.ahara_infra_project.role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "InvokePlatformMigrationLambdas"
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        "arn:aws:lambda:*:${local.account_id}:function:ahara-db-migrate-truenas",
        "arn:aws:lambda:*:${local.account_id}:function:ahara-ci-history-migrate",
      ]
    }]
  })
}
