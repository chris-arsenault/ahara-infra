module "project_ahara_observability" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["ahara-observability"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "ahara-observability"
  state_key_prefix = "projects/ahara-observability"

  module_bundles = []

  policy_modules = [
    "komodo-deploy",
  ]
}

