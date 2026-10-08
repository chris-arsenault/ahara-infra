module "project_pdfree" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["pdfree"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "pdfree"
  state_key_prefix = "projects/pdfree"
  module_bundles   = ["website"]
  policy_modules   = ["terraform-state"]
}
