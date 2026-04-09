data "aws_iam_policy_document" "this" {
  statement {
    sid    = "CognitoClientManagement"
    effect = "Allow"
    actions = [
      "cognito-idp:CreateUserPoolClient",
      "cognito-idp:UpdateUserPoolClient",
      "cognito-idp:DeleteUserPoolClient",
      "cognito-idp:DescribeUserPoolClient"
    ]
    resources = ["arn:aws:cognito-idp:*:${var.account_id}:userpool/*"]
  }
}
