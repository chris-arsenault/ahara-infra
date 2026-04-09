module "project_websites" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["websites"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "websites"
  state_key_prefix = "projects/websites"

  module_bundles = ["website", "alb-api"]

  policy_modules = [
    "terraform-state",
    "dynamodb",
    "bedrock-inference",
  ]
}
