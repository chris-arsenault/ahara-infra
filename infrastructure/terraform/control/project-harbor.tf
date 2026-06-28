module "project_harbor" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["harbor"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "harbor"
  state_key_prefix = "projects/harbor"

  module_bundles = ["cognito-app"]

  policy_modules = [
    "terraform-state",
    "komodo-deploy",
    "ssm-write",
  ]

  ssm_additional_parameter_paths = [
    "ahara/cognito/*",
    "ahara/auth-trigger/clients/*",
    "ahara/harbor/*",
  ]
}
