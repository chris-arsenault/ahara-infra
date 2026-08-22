module "project_glass_frontier" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["the-glass-frontier"]
  allowed_branches   = ["main"]
  allow_pull_request = false

  prefix           = "glass-frontier"
  state_key_prefix = "projects/glass-frontier"

  policy_modules = [
    "acm-dns",
    "alb-target-group",
    "bedrock-inference",
    "cloudfront-distribution",
    "cognito-client",
    "cognito-pool",
    "db-migrate",
    "dynamodb",
    "iam-roles",
    "lambda-deploy",
    "s3-bucket-policy",
    "s3-website",
    "sqs",
    "terraform-state",
  ]
}
