module "project_shuttlecraft" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["shuttlecraft"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "shuttlecraft"
  state_key_prefix = "projects/shuttlecraft"

  module_bundles = []

  policy_modules = [
    "terraform-state",
    "komodo-deploy",
  ]
}
