module "project_arconis" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id
  github_pat        = local.github_pat

  allowed_repos      = ["arconis"]
  allowed_branches   = ["main"]
  allow_pull_request = true
  prefix             = "arconis"
  state_key_prefix   = "projects/arconis"
  module_bundles     = ["website"]
  policy_modules = [
    "terraform-state",
    "ec2-vpc-compute",
    "ec2-security-groups",
    "iam-instance-profiles",
    "alb-target-group",
    "s3-private-storage",
    "ssm-write",
    "cognito-pool",
    "cognito-client",
    "dynamodb",
    "pipeline",
  ]

  ssm_additional_parameter_paths = [
    "ahara/arconis/*",
  ]
}
