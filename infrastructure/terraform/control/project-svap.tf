module "project_svap" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["svap"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "svap"
  state_key_prefix = "projects/svap"

  module_bundles = ["website", "alb-api", "cognito-app"]

  policy_modules = [
    "terraform-state",
    "bedrock-inference",
    "db-migrate",
  ]
}
