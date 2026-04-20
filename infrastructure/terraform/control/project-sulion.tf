module "project_sulion" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["sulion"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "sulion"
  state_key_prefix = "projects/sulion"

  module_bundles = []

  policy_modules = [
    "terraform-state",
    "komodo-deploy",
  ]
}
