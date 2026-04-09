data "aws_iam_policy_document" "this" {
  # Key management cannot be scoped by prefix because KMS key ARNs use
  # UUIDs assigned by AWS at creation time. Scoping is enforced via the
  # alias (which IS prefix-scoped) and by tag conditions where supported.
  statement {
    sid    = "KmsKeyManage"
    effect = "Allow"
    actions = [
      "kms:CreateKey",
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:PutKeyPolicy",
      "kms:EnableKeyRotation",
      "kms:DisableKeyRotation",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ListResourceTags",
      "kms:UpdateKeyDescription",
    ]
    resources = ["*"]
  }

  # List operations are unscoped by design.
  statement {
    sid    = "KmsList"
    effect = "Allow"
    actions = [
      "kms:ListKeys",
      "kms:ListAliases",
    ]
    resources = ["*"]
  }

  # Aliases CAN be scoped by prefix.
  statement {
    sid    = "KmsAliasManage"
    effect = "Allow"
    actions = [
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:UpdateAlias",
    ]
    resources = [
      "arn:aws:kms:*:${var.account_id}:alias/${var.prefix}-*",
      "arn:aws:kms:*:${var.account_id}:key/*",
    ]
  }
}
