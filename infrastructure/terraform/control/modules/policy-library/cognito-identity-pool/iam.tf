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
}
