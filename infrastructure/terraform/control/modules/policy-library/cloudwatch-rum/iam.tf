locals {
  app_monitor_arn = "arn:aws:rum:*:${var.account_id}:appmonitor/${var.prefix}-*"
}

data "aws_iam_policy_document" "this" {
  statement {
    sid    = "CloudWatchRumAppMonitors"
    effect = "Allow"
    actions = [
      "rum:BatchCreateRumMetricDefinitions",
      "rum:BatchDeleteRumMetricDefinitions",
      "rum:BatchGetRumMetricDefinitions",
      "rum:CreateAppMonitor",
      "rum:DeleteAppMonitor",
      "rum:DeleteResourcePolicy",
      "rum:DeleteRumMetricsDestination",
      "rum:GetAppMonitor",
      "rum:GetAppMonitorData",
      "rum:GetResourcePolicy",
      "rum:ListRumMetricsDestinations",
      "rum:PutResourcePolicy",
      "rum:PutRumMetricsDestination",
      "rum:TagResource",
      "rum:UntagResource",
      "rum:UpdateAppMonitor",
      "rum:UpdateRumMetricDefinition",
    ]
    resources = [local.app_monitor_arn]
  }

  statement {
    sid    = "CloudWatchRumList"
    effect = "Allow"
    actions = [
      "rum:ListAppMonitors",
      "rum:ListTagsForResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "CreateRumServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["rum.amazonaws.com"]
    }
  }

  statement {
    sid     = "ReadRumServiceLinkedRole"
    effect  = "Allow"
    actions = ["iam:GetRole"]
    resources = [
      "arn:aws:iam::${var.account_id}:role/aws-service-role/rum.amazonaws.com/AWSServiceRoleForCloudWatchRUM",
    ]
  }
}
