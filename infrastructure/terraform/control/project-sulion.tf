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

  module_bundles = ["alb-api-truenas", "cognito-app"]

  policy_modules = [
    "terraform-state",
    "komodo-deploy",
    "secrets-manager",
    "ssm-write",
    # The transcript archive bucket (sulion-archive-<account>) is created and
    # configured by the project's own Terraform on deploy.
    "s3-private-storage",
  ]

  ssm_additional_parameter_paths = [
    "ahara/cognito/*",
    "ahara/auth-trigger/clients/*",
    "ahara/sulion/*",
    # Its own machine roles publish their ARNs here for the deploy to read.
    "ahara/machines/workloads/sulion/*",
  ]
}

# Only the temporary upload bucket needs policy and ownership management.
resource "aws_iam_role_policy" "sulion_upload_bucket" {
  name = "sulion-upload-bucket-configuration"
  role = module.project_sulion.role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetBucketPolicy", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
        "s3:GetBucketOwnershipControls", "s3:PutBucketOwnershipControls", "s3:DeleteBucketOwnershipControls",
      ]
      Resource = "arn:aws:s3:::sulion-uploads-${local.account_id}"
    }]
  })
}
