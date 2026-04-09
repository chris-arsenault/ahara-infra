locals {
  migrations_bucket = "ahara-migrations-${var.account_id}"

  # Object key prefixes this policy grants write access to.
  # - migrations/{prefix}/*: per-project DB migration SQL files
  # - ahara/*: shared-infra artifacts (og-server binary, etc.),
  #   only granted when the project prefix is "ahara"
  migrations_bucket_prefixes = var.prefix == "ahara" ? [
    "arn:aws:s3:::${local.migrations_bucket}/migrations/${var.prefix}/*",
    "arn:aws:s3:::${local.migrations_bucket}/ahara/*",
    ] : [
    "arn:aws:s3:::${local.migrations_bucket}/migrations/${var.prefix}/*",
  ]
}

data "aws_iam_policy_document" "this" {
  statement {
    sid    = "MigrationsBucketManagement"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucketLocation",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutEncryptionConfiguration",
      "s3:Get*"
    ]
    resources = ["arn:aws:s3:::${local.migrations_bucket}"]
  }

  # The migrations bucket has versioning enabled, so delete operations
  # on individual object versions require s3:DeleteObjectVersion.
  # Object tagging perms are required because provider-level default_tags
  # apply to aws_s3_object resources on put.
  statement {
    sid    = "MigrationsBucketReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectTagging",
      "s3:GetObjectVersionTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:PutObjectVersionTagging",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:DeleteObjectTagging",
      "s3:DeleteObjectVersionTagging",
    ]
    resources = local.migrations_bucket_prefixes
  }

  statement {
    sid       = "InvokeMigrateLambda"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = ["arn:aws:lambda:*:${var.account_id}:function:ahara-db-migrate"]
  }
}
