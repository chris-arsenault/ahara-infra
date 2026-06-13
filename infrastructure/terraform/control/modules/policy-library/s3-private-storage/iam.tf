locals {
  s3_bucket_namespace_arn = "arn:aws:s3:::${var.prefix}-*"
  s3_object_namespace_arn = "arn:aws:s3:::${var.prefix}-*/*"
}

data "aws_iam_policy_document" "this" {
  # S3 bucket creation cannot be scoped to an ARN because the bucket does
  # not exist yet. Management after creation is scoped to prefix-* buckets.
  statement {
    sid       = "PrivateStorageBucketCreate"
    effect    = "Allow"
    actions   = ["s3:CreateBucket"]
    resources = ["*"]
  }

  statement {
    sid    = "PrivateStorageBucketManagement"
    effect = "Allow"
    actions = [
      "s3:DeleteBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketNotification",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketCORS",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetObjectLockConfiguration",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:PutBucketCORS",
      "s3:PutBucketNotification",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:PutObjectLockConfiguration",
    ]
    resources = [local.s3_bucket_namespace_arn]
  }

  statement {
    sid    = "PrivateStorageObjectManagement"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectTagging",
      "s3:DeleteObjectVersion",
      "s3:DeleteObjectVersionTagging",
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:GetObjectVersion",
      "s3:GetObjectVersionTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:PutObjectVersionTagging",
    ]
    resources = [local.s3_object_namespace_arn]
  }

  statement {
    sid    = "KmsForPrivateStorage"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.us-east-1.amazonaws.com"]
    }
  }
}
