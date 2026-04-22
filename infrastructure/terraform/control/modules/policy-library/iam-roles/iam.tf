data "aws_iam_policy_document" "this" {
  statement {
    sid    = "ManageRolesAndPolicies"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:Get*",
      "iam:List*",
      "iam:ListInstanceProfilesForRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:TagPolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:CreatePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:DeletePolicy",
      "iam:UntagPolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
    ]
    resources = [
      "arn:aws:iam::${var.account_id}:role/${var.prefix}-*",
      "arn:aws:iam::${var.account_id}:policy/${var.prefix}-*",
      "arn:aws:iam::${var.account_id}:policy/deployer-*"
    ]
  }
}
