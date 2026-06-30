data "aws_iam_policy_document" "truenas_workload_boundary" {
  statement {
    sid    = "S3ProjectStorage"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
    ]
    resources = [
      "arn:aws:s3:::${var.prefix}-*",
      "arn:aws:s3:::${var.prefix}-*/*",
      "arn:aws:s3:::ahara-${var.prefix}-*",
      "arn:aws:s3:::ahara-${var.prefix}-*/*",
    ]
  }

  statement {
    sid    = "InvokeProjectLambdas"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction",
    ]
    resources = [
      "arn:aws:lambda:*:${var.account_id}:function:${var.prefix}-*",
      "arn:aws:lambda:*:${var.account_id}:function:${var.prefix}-*:*",
    ]
  }

  statement {
    sid    = "ReadProjectParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      "arn:aws:ssm:*:${var.account_id}:parameter/${var.prefix}/*",
    ]
  }
}

resource "aws_iam_policy" "truenas_workload_boundary" {
  name   = "pb-${var.prefix}-truenas-workload"
  policy = data.aws_iam_policy_document.truenas_workload_boundary.json
  tags   = local.tags
}
