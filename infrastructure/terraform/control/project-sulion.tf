module "project_sulion" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["sulion"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "sulion"
  state_key_prefix = "projects/sulion"

  module_bundles = ["cognito-app"]

  policy_modules = [
    "terraform-state",
    "komodo-deploy",
    "ssm-write",
  ]

  ssm_additional_parameter_paths = [
    "ahara/cognito/*",
    "ahara/auth-trigger/clients/*",
    "ahara/sulion/*",
  ]
}
