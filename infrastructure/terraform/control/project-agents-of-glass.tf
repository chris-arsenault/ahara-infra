module "project_agents_of_glass" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["agents-of-glass"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "agents-of-glass"
  state_key_prefix = "projects/agents-of-glass"

  module_bundles = ["website", "alb-api"]

  policy_modules = [
    "terraform-state",
    "db-migrate",
  ]
}
