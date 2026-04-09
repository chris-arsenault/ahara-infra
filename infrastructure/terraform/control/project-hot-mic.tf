module "project_hot_mic" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["hot-mic"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "hot-mic"
  state_key_prefix = "projects/hot-mic"
  policy_modules = [
    "terraform-state",
  ]
}
