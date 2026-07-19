locals {
  repo_bucket_arn  = "arn:aws:s3:::ahara-fdroid-*"
  repo_object_arn  = "arn:aws:s3:::ahara-fdroid-*/*"
  keys_bucket_arn  = "arn:aws:s3:::ahara-fdroid-keys-*"
  keys_object_arn  = "arn:aws:s3:::ahara-fdroid-keys-*/*"
  distribution_arn = "arn:aws:cloudfront::${var.account_id}:distribution/*"
}

data "aws_iam_policy_document" "this" {
  statement {
    sid    = "FdroidRepoBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [local.repo_bucket_arn]
  }

  statement {
    sid    = "FdroidRepoObjectPublish"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
      "s3:PutObjectTagging",
    ]
    resources = [local.repo_object_arn]
  }

  statement {
    sid    = "FdroidSigningBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [local.keys_bucket_arn]
  }

  statement {
    sid    = "FdroidSigningObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [local.keys_object_arn]
  }

  statement {
    sid    = "FdroidCloudFrontInvalidation"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
    ]
    resources = [local.distribution_arn]
  }
}

output "policy_json" {
  value = data.aws_iam_policy_document.this.json
}
