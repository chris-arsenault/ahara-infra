module "project_arcade_actions" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["arcade-actions"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "arcade-actions"
  state_key_prefix = "projects/arcade-actions"
  module_bundles   = ["website"]
  policy_modules   = ["terraform-state"]
}
