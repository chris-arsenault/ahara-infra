# =============================================================================
# foundry-vtt deployer role
#
# Foundry Virtual Tabletop game server at foundry.ahara.io: a stop-when-idle
# EC2 instance behind the shared ALB, worlds on EFS, game media in a
# public-read S3 bucket (Foundry's native S3 integration), woken by a Discord
# slash-command Lambda. No RDS, no Cognito — Foundry brings its own auth.
# =============================================================================

module "project_foundry_vtt" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["foundry-vtt"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "foundry-vtt"
  state_key_prefix = "projects/foundry-vtt"

  policy_modules = [
    "terraform-state",
    "ec2-vpc-compute",
    "ec2-security-groups",
    "iam-roles",
    "iam-instance-profiles",
    "alb-target-group",
    "acm-dns",
    "lambda-deploy",
    "s3-private-storage",
    "s3-bucket-policy",
    "efs",
    "ssm-write",
  ]

  ssm_additional_parameter_paths = [
    "ahara/foundry-vtt/*",
  ]
}
