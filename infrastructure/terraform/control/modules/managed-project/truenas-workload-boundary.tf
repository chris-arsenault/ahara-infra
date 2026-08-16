data "aws_region" "truenas_workload_boundary" {}

variable "truenas_workload_cross_project_parameter_prefixes" {
  description = "Other projects whose parameters this project's workloads may read. Declared centrally, because reaching another project's secrets is a platform decision rather than a project one."
  type        = list(string)
  default     = []
}

data "aws_iam_policy_document" "truenas_workload_boundary" {
  statement {
    sid    = "DenyIdentityAdministration"
    effect = "Deny"
    actions = [
      "account:*",
      "iam:*",
      "identitystore:*",
      "organizations:*",
      "sso:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyCognitoUserAdministration"
    effect = "Deny"
    actions = [
      "cognito-idp:Admin*",
      "cognito-idp:CreateGroup",
      "cognito-idp:CreateUserPool*",
      "cognito-idp:DeleteGroup",
      "cognito-idp:DeleteUserPool*",
      "cognito-idp:UpdateGroup",
      "cognito-idp:UpdateUserPool*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyMarketplace"
    effect = "Deny"
    actions = [
      "aws-marketplace:*",
      "aws-marketplace-management:*",
      "marketplacecommerceanalytics:*",
    ]
    resources = ["*"]
  }

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

  # The ceiling on what this project's own Terraform may grant a workload:
  # its parameters, and any other project's it is centrally declared to read.
  # The role created in the project repository grants within this, so reaching
  # another project's parameters takes a change on both sides (ahara-trust
  # ADR-0002).
  #
  # Every path is under /ahara/, which is where parameters actually live.
  statement {
    sid    = "ReadProjectParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = concat(
      [
        "arn:aws:ssm:*:${var.account_id}:parameter/ahara/${var.prefix}/*",
        "arn:aws:ssm:*:${var.account_id}:parameter/ahara/truenas-db/${var.prefix}/*",
      ],
      [
        for p in var.truenas_workload_cross_project_parameter_prefixes :
        "arn:aws:ssm:*:${var.account_id}:parameter/ahara/${p}/*"
      ],
    )
  }

  # Those parameters are SecureString, so reading one is also a KMS decrypt.
  # Scoped to calls SSM makes on the workload's behalf, so it is not usable
  # against anything else the key protects.
  statement {
    sid       = "DecryptProjectParameters"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.truenas_workload_boundary.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "truenas_workload_boundary" {
  name   = "pb-${var.prefix}-truenas-workload"
  policy = data.aws_iam_policy_document.truenas_workload_boundary.json
  tags   = local.tags
}
