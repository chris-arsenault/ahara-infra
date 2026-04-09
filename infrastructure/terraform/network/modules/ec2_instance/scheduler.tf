data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name_prefix        = "${var.name}-scheduler-"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler_permissions" {
  statement {
    actions = [
      "autoscaling:StartInstanceRefresh"
    ]
    resources = [aws_autoscaling_group.this.arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${var.name}-scheduler-policy"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_permissions.json
}

resource "aws_scheduler_schedule" "nightly_refresh" {
  name        = substr(local.schedule_name, 0, 52)
  description = "Nightly instance refresh for ${var.name}"

  schedule_expression = var.refresh_cron_expression

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:autoscaling:startInstanceRefresh"
    role_arn = aws_iam_role.scheduler.arn
    input = jsonencode({
      AutoScalingGroupName = aws_autoscaling_group.this.name
      Preferences = {
        MinHealthyPercentage = 0
      }
    })
  }
}
