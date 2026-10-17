# Admission only. Atlas owns its workflow, workers, output bucket and registry row.
module "project_atlas" {
  source             = "./modules/managed-project"
  oidc_provider_arn  = aws_iam_openid_connect_provider.github.arn
  account_id         = local.account_id
  github_pat         = local.github_pat
  allowed_repos      = ["atlas"]
  allowed_branches   = ["main"]
  allow_pull_request = true
  prefix             = "atlas"
  state_key_prefix   = "projects/atlas"
  module_bundles     = ["website", "lambda", "pipeline"]
  policy_modules     = ["terraform-state", "s3-private-storage", "s3-bucket-policy", "grafana-dashboard-deploy"]
}
