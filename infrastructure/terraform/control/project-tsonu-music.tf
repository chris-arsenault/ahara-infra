module "project_tsonu_music" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["tsonu-music"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "tsonu-music"
  state_key_prefix = "projects/tsonu-music"

  module_bundles = ["website"]

  policy_modules = [
    "terraform-state",
  ]
}
