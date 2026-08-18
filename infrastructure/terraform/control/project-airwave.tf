module "project_airwave" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["airwave"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "airwave"
  state_key_prefix = "projects/airwave"
  module_bundles   = ["website", "cognito-app"]
  policy_modules = [
    "terraform-state",
    "alb-target-group",
    "komodo-deploy",
    "fdroid-publish",
    # Its machine role publishes its ARN to SSM, which is what the paths below
    # permit — and they permit nothing without this module, since that is what
    # consumes them. harbor and sulion already carry it.
    "ssm-write",
  ]

  ssm_additional_parameter_paths = [
    # Its own machine role publishes its ARN here for the deploy to read.
    "ahara/machines/workloads/airwave/*",
  ]
}
