module "project_nas_sonarqube" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["nas-sonarqube"]
  allowed_branches   = ["main"]
  allow_pull_request = true

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
