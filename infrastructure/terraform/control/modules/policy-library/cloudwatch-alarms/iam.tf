locals {
  cloudwatch_alarm_namespace_arn = "arn:aws:cloudwatch:*:${var.account_id}:alarm:${var.prefix}-*"
}

data "aws_iam_policy_document" "this" {
  statement {
    sid    = "CloudWatchAlarmManagement"
    effect = "Allow"
    actions = [
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:DisableAlarmActions",
      "cloudwatch:EnableAlarmActions",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]
    resources = [local.cloudwatch_alarm_namespace_arn]
  }
}
