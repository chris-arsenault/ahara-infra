module "project_nas_sonarqube" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  # Retirement barrier: revoke GitHub trust and repository secrets before the
  # deployer role and its state access are removed in the following apply.
  github_pat         = local.github_pat
  allowed_repos      = []
  allowed_branches   = ["main"]
  allow_pull_request = false

  prefix           = "nas-sonarqube"
  state_key_prefix = "projects/nas-sonarqube"

  module_bundles = ["lambda", "cognito-app"]

  policy_modules = [
    "terraform-state",
    "komodo-deploy",
  ]

  ssm_additional_parameter_paths = [
    "ahara/sonarqube/*",
    "ahara/auth-trigger/clients/*"
  ]
}
