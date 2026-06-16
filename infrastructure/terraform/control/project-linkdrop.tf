module "project_linkdrop" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["bookmarker"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "linkdrop"
  state_key_prefix = "projects/linkdrop"

  module_bundles = ["website", "alb-api", "cognito-app", "lambda"]

  ssm_additional_parameter_paths = ["ahara/auth-trigger/clients/linkdrop-app"]

  policy_modules = [
    "terraform-state",
    "db-migrate",
    "s3-private-storage",
    "ssm-write",
    "cloudwatch-alarms",
  ]
}
