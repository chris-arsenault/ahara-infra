module "project_antropy" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["antropy"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "antropy"
  state_key_prefix = "projects/antropy"

  module_bundles = ["website"]

  policy_modules = [
    "terraform-state",
    "komodo-deploy",
    "ssm-write",
  ]

  ssm_additional_parameter_paths = [
    "ahara/antropy/operator-token",
  ]
}
