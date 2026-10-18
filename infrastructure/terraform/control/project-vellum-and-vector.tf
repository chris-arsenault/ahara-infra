module "project_vellum_and_vector" {
  source = "./modules/managed-project"

  oidc_provider_arn  = aws_iam_openid_connect_provider.github.arn
  account_id         = local.account_id
  github_pat         = local.github_pat
  allowed_repos      = ["vellum-and-vector"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "vellum-and-vector"
  state_key_prefix = "projects/vellum-and-vector"
  module_bundles   = ["website"]
  policy_modules   = ["terraform-state"]
}
