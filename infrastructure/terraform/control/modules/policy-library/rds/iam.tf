data "aws_iam_policy_document" "this" {
  statement {
    sid    = "RdsInstances"
    effect = "Allow"
    actions = [
      "rds:CreateDBInstance",
      "rds:DeleteDBInstance",
      "rds:ModifyDBInstance",
      "rds:DescribeDBInstances",
      "rds:AddTagsToResource",
      "rds:RemoveTagsFromResource",
      "rds:ListTagsForResource"
    ]
    resources = ["arn:aws:rds:*:${var.account_id}:db:${var.prefix}-*"]
  }

  statement {
    sid    = "RdsSubnetGroups"
    effect = "Allow"
    actions = [
      "rds:CreateDBSubnetGroup",
      "rds:DeleteDBSubnetGroup",
      "rds:DescribeDBSubnetGroups",
      "rds:ModifyDBSubnetGroup",
      "rds:AddTagsToResource",
      "rds:RemoveTagsFromResource",
      "rds:ListTagsForResource"
    ]
    resources = ["arn:aws:rds:*:${var.account_id}:subgrp:${var.prefix}-*"]
  }
}
