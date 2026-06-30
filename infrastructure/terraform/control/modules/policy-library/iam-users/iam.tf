data "aws_iam_policy_document" "this" {
  statement {
    sid    = "ManagePrefixedUsersAndAccessKeys"
    effect = "Allow"
    actions = [
      "iam:CreateAccessKey",
      "iam:CreateUser",
      "iam:DeleteAccessKey",
      "iam:DeleteUser",
      "iam:DeleteUserPolicy",
      "iam:GetAccessKeyLastUsed",
      "iam:GetUser",
      "iam:GetUserPolicy",
      "iam:ListAccessKeys",
      "iam:ListAttachedUserPolicies",
      "iam:ListGroupsForUser",
      "iam:ListUserTags",
      "iam:ListUserPolicies",
      "iam:PutUserPolicy",
      "iam:TagUser",
      "iam:UntagUser",
      "iam:UpdateAccessKey",
    ]
    resources = ["arn:aws:iam::${var.account_id}:user/${var.prefix}-*"]
  }
}
