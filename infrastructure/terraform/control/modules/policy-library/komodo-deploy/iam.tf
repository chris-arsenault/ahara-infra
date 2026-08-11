data "aws_iam_policy_document" "this" {
  statement {
    sid    = "InvokeKomodoProxy"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      "arn:aws:lambda:*:${var.account_id}:function:ahara-komodo-proxy",
      "arn:aws:lambda:*:${var.account_id}:function:ahara-db-migrate-truenas"
    ]
  }

  statement {
    sid    = "ReadRolesAnywhereDiscovery"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      # Discovery only: where to authenticate. Identities are issued on the
      # LAN by the trust appliance, so nothing here mints or consumes
      # enrollment credentials.
      "arn:aws:ssm:*:${var.account_id}:parameter/ahara/machines/*",
    ]
  }

  statement {
    sid    = "CreateBoundedTrueNasWorkloadRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
    ]
    resources = [
      "arn:aws:iam::${var.account_id}:role/${var.prefix}-truenas-*",
      "arn:aws:iam::${var.account_id}:role/${var.prefix}/truenas/${var.prefix}-truenas-*",
      "arn:aws:iam::${var.account_id}:role/ahara-machine-${var.prefix}-*",
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = ["arn:aws:iam::${var.account_id}:policy/pb-${var.prefix}-truenas-workload"]
    }
  }

  statement {
    sid    = "ManageTrueNasWorkloadRoles"
    effect = "Allow"
    actions = [
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = [
      "arn:aws:iam::${var.account_id}:role/${var.prefix}-truenas-*",
      "arn:aws:iam::${var.account_id}:role/${var.prefix}/truenas/${var.prefix}-truenas-*",
      "arn:aws:iam::${var.account_id}:role/ahara-machine-${var.prefix}-*",
    ]
  }
}
