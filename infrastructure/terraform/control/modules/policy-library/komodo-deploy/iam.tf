data "aws_iam_policy_document" "this" {
  statement {
    sid    = "InvokeKomodoProxy"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      "arn:aws:lambda:*:${var.account_id}:function:ahara-komodo-proxy",
      "arn:aws:lambda:*:${var.account_id}:function:ahara-db-migrate-truenas",
      "arn:aws:lambda:*:${var.account_id}:function:nas-sonarqube-ci-token"
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
      "arn:aws:ssm:*:${var.account_id}:parameter/ahara/truenas-roles-anywhere/*",
    ]
  }

  statement {
    sid    = "WriteRolesAnywhereEnrollmentTokens"
    effect = "Allow"
    actions = [
      "ssm:DeleteParameter",
      "ssm:GetParameter",
      "ssm:PutParameter",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
      "ssm:ListTagsForResource",
    ]
    resources = [
      "arn:aws:ssm:*:${var.account_id}:parameter/ahara/truenas-roles-anywhere/enrollment/${var.prefix}/*",
      "arn:aws:ssm:*:${var.account_id}:parameter/ahara/truenas-roles-anywhere/workloads/${var.prefix}/*",
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
    ]
  }
}
