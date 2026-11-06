module "project_arconis" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id
  github_pat        = local.github_pat

  allowed_repos      = ["arconis"]
  allowed_branches   = ["main"]
  allow_pull_request = true
  prefix             = "arconis"
  state_key_prefix   = "projects/arconis"
  module_bundles     = ["website"]
  policy_modules     = ["terraform-state", "appsync-events"]
}
