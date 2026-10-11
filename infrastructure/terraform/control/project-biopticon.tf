module "project_biopticon" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["biopticon"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "biopticon"
  state_key_prefix = "projects/biopticon-probe"
  module_bundles   = ["alb-api", "cognito-app"]

  policy_modules = [
    "terraform-state",
    "s3-private-storage",
    # The private event bucket enforces TLS and conditional creation.
    "s3-bucket-policy",
    "ssm-write",
  ]

  ssm_additional_parameter_paths = [
    "ahara/auth-trigger/clients/biopticon-probe-mobile",
  ]
}
