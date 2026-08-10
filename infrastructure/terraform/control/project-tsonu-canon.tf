module "project_tsonu_canon" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["tsonu-canon"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "tsonu-canon"
  state_key_prefix = "projects/tsonu-canon"

  module_bundles = ["website", "alb-api", "cognito-app"]

  policy_modules = [
    "terraform-state",
    "s3-private-storage",
  ]
}
