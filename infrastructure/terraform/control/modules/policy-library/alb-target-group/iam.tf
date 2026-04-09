data "aws_iam_policy_document" "this" {
  # Create actions require wildcard because the resource does not exist yet.
  statement {
    sid    = "CreateAlbTargetResources"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:AddTags"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageAlbTargetResources"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:${var.account_id}:targetgroup/${var.prefix}-*/*",
      "arn:aws:elasticloadbalancing:*:${var.account_id}:listener-rule/app/*/*/*/*",
      "arn:aws:elasticloadbalancing:*:${var.account_id}:listener/app/*/*/*"
    ]
  }
}
