data "aws_iam_policy_document" "this" {
  # Create actions require wildcard because the resource does not exist yet.
  statement {
    sid    = "CreateAlbLoadBalancer"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateListener",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageAlbLoadBalancer"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:SetWebACL",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:*:${var.account_id}:loadbalancer/app/${var.prefix}-*",
      "arn:aws:elasticloadbalancing:*:${var.account_id}:listener/app/${var.prefix}-*/*/*"
    ]
  }
}
