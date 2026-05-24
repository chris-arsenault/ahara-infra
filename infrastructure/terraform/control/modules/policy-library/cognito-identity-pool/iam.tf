data "aws_iam_policy_document" "this" {
  statement {
    sid    = "CognitoIdentityPools"
    effect = "Allow"
    actions = [
      "cognito-identity:CreateIdentityPool",
      "cognito-identity:DeleteIdentityPool",
      "cognito-identity:DescribeIdentityPool",
      "cognito-identity:GetIdentityPoolRoles",
      "cognito-identity:SetIdentityPoolRoles",
      "cognito-identity:UpdateIdentityPool",
      "cognito-identity:TagResource",
      "cognito-identity:UntagResource"
    ]
    resources = ["arn:aws:cognito-identity:*:${var.account_id}:identitypool/*"]
  }

  statement {
    sid       = "PassPrefixedRolesToCognitoIdentity"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.account_id}:role/${var.prefix}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["cognito-identity.amazonaws.com"]
    }
  }
}
