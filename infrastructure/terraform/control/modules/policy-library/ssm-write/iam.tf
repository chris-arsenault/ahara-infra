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
      "ssm:PutParameter",
      "ssm:DeleteParameter",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
      "ssm:ListTagsForResource"
    ]
    resources = local.parameter_paths
  }
}
