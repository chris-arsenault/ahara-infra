locals {
  state_bucket = "tfstate-${var.account_id}"
}

data "aws_iam_policy_document" "this" {
  statement {
    sid    = "TerraformStateList"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketVersioning"
    ]
    resources = ["arn:aws:s3:::${local.state_bucket}"]
  }

  statement {
    sid    = "TerraformStateReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = ["arn:aws:s3:::${local.state_bucket}/${var.state_key_prefix}*"]
  }
}
