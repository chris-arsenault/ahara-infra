locals {
  vector_log_roles = {
    nat = {
      role_name     = aws_iam_role.nat.name
      log_group_arn = aws_cloudwatch_log_group.nat.arn
    }
    reverse_proxy = {
      role_name     = aws_iam_role.reverse_proxy.name
      log_group_arn = aws_cloudwatch_log_group.reverse_proxy.arn
    }
    wireguard = {
      role_name     = aws_iam_role.wireguard.name
      log_group_arn = aws_cloudwatch_log_group.wireguard.arn
    }
  }
}

data "aws_iam_policy_document" "vector_cloudwatch_logs" {
  for_each = local.vector_log_roles

  statement {
    sid = "DescribeLogGroups"
    actions = [
      "logs:DescribeLogGroups"
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageNamespace"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]
    resources = [
      each.value.log_group_arn,
      "${each.value.log_group_arn}:log-stream:*"
    ]
  }
}

resource "aws_iam_role_policy" "vector_cloudwatch_logs" {
  for_each = local.vector_log_roles

  name   = "${local.prefix}-${each.key}-vector-cw"
  role   = each.value.role_name
  policy = data.aws_iam_policy_document.vector_cloudwatch_logs[each.key].json
}
