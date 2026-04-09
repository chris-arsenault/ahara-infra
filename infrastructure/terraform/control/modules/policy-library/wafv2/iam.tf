data "aws_iam_policy_document" "this" {
  statement {
    sid    = "Wafv2WebAclManage"
    effect = "Allow"
    actions = [
      "wafv2:CreateWebACL",
      "wafv2:DeleteWebACL",
      "wafv2:UpdateWebACL",
      "wafv2:GetWebACL",
      "wafv2:TagResource",
      "wafv2:UntagResource",
      "wafv2:ListTagsForResource"
    ]
    resources = [
      # Regional WebACLs (ALB, API Gateway, etc.)
      "arn:aws:wafv2:*:${var.account_id}:regional/webacl/${var.prefix}-*/*",
      "arn:aws:wafv2:*:${var.account_id}:regional/managedruleset/*/*",
      # Global/CloudFront WebACLs — must live in us-east-1
      "arn:aws:wafv2:us-east-1:${var.account_id}:global/webacl/${var.prefix}-*/*",
      "arn:aws:wafv2:us-east-1:${var.account_id}:global/managedruleset/*/*"
    ]
  }

  # List operations cannot be scoped to a specific resource.
  statement {
    sid    = "Wafv2List"
    effect = "Allow"
    actions = [
      "wafv2:ListWebACLs"
    ]
    resources = ["*"]
  }

  # Associate/Disassociate require the target resource ARN (ALB, CloudFront, etc.)
  # which cannot be predicted by prefix.
  statement {
    sid    = "Wafv2Associate"
    effect = "Allow"
    actions = [
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
    ]
    resources = ["*"]
  }
}
