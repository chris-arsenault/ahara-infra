locals {
  parameter_paths = concat(
    ["arn:aws:ssm:*:${var.account_id}:parameter/${var.prefix}/*"],
    [for p in var.additional_parameter_paths : "arn:aws:ssm:*:${var.account_id}:parameter/${p}"]
  )
}

data "aws_iam_policy_document" "this" {
  statement {
    sid    = "SsmParameterWrite"
    effect = "Allow"
    actions = [
      "ssm:AddTagsToResource",
      "ssm:DeleteParameter",
      "ssm:DescribeParameters",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListTagsForResource",
      "ssm:PutParameter",
      "ssm:RemoveTagsFromResource",
    ]
    resources = local.parameter_paths
  }
}
