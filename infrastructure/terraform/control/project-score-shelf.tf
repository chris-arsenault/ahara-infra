module "project_score_shelf" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["score-shelf"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "score-shelf"
  state_key_prefix = "projects/score-shelf"

  module_bundles = ["website", "alb-api", "cognito-app"]

  ssm_additional_parameter_paths = ["ahara/auth-trigger/clients/score-shelf-app"]

  policy_modules = [
    "terraform-state",
    "db-migrate",
    "s3-private-storage",
    "ssm-write",
    "cloudwatch-alarms",
  ]
}
