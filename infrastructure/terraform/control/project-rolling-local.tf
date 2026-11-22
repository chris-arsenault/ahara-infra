module "project_rolling_local" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id
  github_pat        = local.github_pat

  allowed_repos      = ["rolling-local"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "rolling-local"
  state_key_prefix = "projects/rolling-local"

  module_bundles = ["website", "alb-api", "cognito-app"]
  policy_modules = [
    "terraform-state",
    "dynamodb",
    "s3-private-storage",
    "s3-bucket-policy",
    "ssm-write",
  ]

  ssm_additional_parameter_paths = ["ahara/auth-trigger/clients/rolling-local"]
}
