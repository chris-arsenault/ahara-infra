module "project_legato" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["legato"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "legato"
  state_key_prefix = "projects/legato"

  module_bundles = []

  policy_modules = [
    "terraform-state",
    "komodo-deploy",
  ]
}
