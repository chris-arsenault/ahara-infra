module "project_catalyst_castellum" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["catalyst-castellum"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "catalyst"
  state_key_prefix = "projects/catalyst-castellum"

  module_bundles = ["website"]

  policy_modules = [
    "terraform-state",
  ]
}
