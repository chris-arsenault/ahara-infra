# =============================================================================
# Observability — Alarms, SNS, Budgets
# =============================================================================

# --- SNS Topic for shared-infra alarms ---

resource "aws_sns_topic" "alarms" {
  name = "${local.prefix}-alarms"
}

resource "aws_sns_topic_policy" "alarms" {
  arn = aws_sns_topic.alarms.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Retain the SNS default permissions for the topic's owning account.
      {
        Sid       = "__default_statement_ID"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action = [
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:AddPermission",
          "SNS:RemovePermission",
          "SNS:DeleteTopic",
          "SNS:Subscribe",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish",
        ]
        Resource = aws_sns_topic.alarms.arn
        Condition = {
          StringEquals = { "AWS:SourceOwner" = data.aws_caller_identity.current.account_id }
        }
      },
      {
        Sid       = "AllowBudgetsPublish"
        Effect    = "Allow"
        Principal = { Service = "budgets.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alarms.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:aws:budgets::${data.aws_caller_identity.current.account_id}:*" }
        }
      },
      {
        Sid       = "AllowCostAnomalyPublish"
        Effect    = "Allow"
        Principal = { Service = "costalerts.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alarms.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "alarms_email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.seed_user_email
}

resource "aws_ssm_parameter" "alarm_topic_arn" {
  name  = "${local.ssm_prefix}/alarms/sns-topic-arn"
  type  = "String"
  value = aws_sns_topic.alarms.arn
}

# --- Budget alert ---

resource "aws_budgets_budget" "monthly" {
  depends_on = [aws_sns_topic_policy.alarms]

  name         = "${local.prefix}-monthly"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alarms.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alarms.arn]
  }
}

# --- Cost anomaly detection ---

resource "aws_ce_anomaly_monitor" "ahara" {
  name              = "${local.prefix}-cost-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "ahara" {
  depends_on = [aws_sns_topic_policy.alarms]

  name = "${local.prefix}-cost-anomaly"

  monitor_arn_list = [aws_ce_anomaly_monitor.ahara.arn]

  frequency = "IMMEDIATE"

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.alarms.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = ["10"]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }
}
