data "aws_iam_policy_document" "this" {
  statement {
    sid    = "CognitoUserPoolAdmin"
    effect = "Allow"
    actions = [
      "cognito-idp:CreateUserPool",
      "cognito-idp:DeleteUserPool",
      "cognito-idp:UpdateUserPool",
      "cognito-idp:DescribeUserPool",
      "cognito-idp:ListUserPoolClients",
      "cognito-idp:AdminCreateUser",
      "cognito-idp:AdminDeleteUser",
      "cognito-idp:AdminGetUser",
      "cognito-idp:AdminSetUserPassword",
      "cognito-idp:AdminAddUserToGroup",
      "cognito-idp:AdminRemoveUserFromGroup",
      "cognito-idp:CreateGroup",
      "cognito-idp:DeleteGroup",
      "cognito-idp:GetGroup",
      "cognito-idp:UpdateGroup",
      "cognito-idp:TagResource",
      "cognito-idp:UntagResource"
    ]
    resources = ["arn:aws:cognito-idp:*:${var.account_id}:userpool/*"]
  }

  # Domain operations require wildcard because the domain resource is not part of the userpool ARN.
  statement {
    sid    = "CognitoUserPoolDomains"
    effect = "Allow"
    actions = [
      "cognito-idp:CreateUserPoolDomain",
      "cognito-idp:DeleteUserPoolDomain",
      "cognito-idp:DescribeUserPoolDomain",
      "cognito-idp:UpdateUserPoolDomain",
    ]
    resources = ["*"]
  }
}
