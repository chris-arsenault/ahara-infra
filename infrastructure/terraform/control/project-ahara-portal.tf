module "project_ahara_portal" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["ahara-portal"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "ahara-portal"
  state_key_prefix = "projects/ahara-portal"

  module_bundles = ["website", "alb-api", "cognito-app"]

  policy_modules = [
    "terraform-state",
    "dynamodb",
  ]

  ssm_additional_parameter_paths = [
    "ahara/cognito/*",
  ]
}
