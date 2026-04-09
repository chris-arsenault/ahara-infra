data "aws_iam_policy_document" "this" {
  statement {
    sid    = "SnsTopics"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource"
    ]
    resources = ["arn:aws:sns:*:${var.account_id}:${var.prefix}-*"]
  }
}
