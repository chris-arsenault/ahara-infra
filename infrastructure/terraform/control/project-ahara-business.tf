module "project_ahara_business" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["ahara-business"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "ahara-business"
  state_key_prefix = "projects/ahara-business"

  module_bundles = ["website", "alb-api", "cognito-app", "lambda"]

  ssm_additional_parameter_paths  = ["ahara/auth-trigger/clients/ahara-business-app"]
  additional_ses_identity_domains = ["ahara.io"]

  policy_modules = [
    "terraform-state",
    "db-migrate",
    "dynamodb",
    "sns",
    "ses",
    "ssm-write",
    "s3-private-storage",
    "cloudwatch-alarms",
  ]
}
