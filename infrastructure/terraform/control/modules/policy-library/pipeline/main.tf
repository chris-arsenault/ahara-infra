variable "prefix" { type = string }
variable "account_id" { type = string }
data "aws_iam_policy_document" "this" {
  statement {
    actions   = ["states:CreateStateMachine", "states:UpdateStateMachine", "states:DeleteStateMachine", "states:DescribeStateMachine", "states:ListTagsForResource", "states:TagResource", "states:UntagResource", "states:StartExecution", "states:ListExecutions"]
    resources = ["arn:aws:states:*:${var.account_id}:stateMachine:${var.prefix}-pipeline-*"]
  }
  statement {
    actions   = ["states:DescribeExecution", "states:GetExecutionHistory", "states:StopExecution", "states:RedriveExecution"]
    resources = ["arn:aws:states:*:${var.account_id}:execution:${var.prefix}-pipeline-*:*"]
  }
  statement {
    actions   = ["scheduler:CreateScheduleGroup", "scheduler:DeleteScheduleGroup", "scheduler:GetScheduleGroup", "scheduler:TagResource", "scheduler:UntagResource", "scheduler:ListTagsForResource"]
    resources = ["arn:aws:scheduler:*:${var.account_id}:schedule-group/${var.prefix}-pipeline-*"]
  }
  statement {
    actions   = ["scheduler:CreateSchedule", "scheduler:UpdateSchedule", "scheduler:DeleteSchedule", "scheduler:GetSchedule"]
    resources = ["arn:aws:scheduler:*:${var.account_id}:schedule/${var.prefix}-pipeline-*/*"]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.account_id}:role/${var.prefix}-pipeline-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["states.amazonaws.com", "scheduler.amazonaws.com"]
    }
  }
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:*:${var.account_id}:table/ahara-pipeline-registry"]
    condition {
      test     = "ForAllValues:StringLike"
      variable = "dynamodb:LeadingKeys"
      values   = ["arn:aws:states:*:${var.account_id}:stateMachine:${var.prefix}-pipeline-*"]
    }
  }
  statement {
    actions   = ["dynamodb:DescribeTable"]
    resources = ["arn:aws:dynamodb:*:${var.account_id}:table/ahara-pipeline-registry"]
  }
  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:*:${var.account_id}:parameter/ahara/pipelines/*"]
  }
}
output "policy_json" { value = data.aws_iam_policy_document.this.json }
