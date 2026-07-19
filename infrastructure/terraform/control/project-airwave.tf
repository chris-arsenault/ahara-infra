module "project_airwave" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["airwave"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "airwave"
  state_key_prefix = "projects/airwave"
  policy_modules = [
    "terraform-state",
    "komodo-deploy",
  ]
}
