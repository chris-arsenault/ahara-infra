module "project_ahara_access" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["ahara-access"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "ahara-access"
  state_key_prefix = "projects/ahara-access"

  module_bundles = ["alb-api"]

  policy_modules = [
    "terraform-state",
    "db-migrate",
    "s3-private-storage",
  ]
}

