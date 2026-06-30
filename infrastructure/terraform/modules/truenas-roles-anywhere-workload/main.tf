locals {
  role_name                = coalesce(var.role_name, "${var.prefix}-truenas-${var.name}")
  workload_id              = "spiffe://ahara/truenas/${var.prefix}/${var.name}"
  permissions_boundary_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/pb-${var.prefix}-truenas-workload"

  tags = merge(var.tags, {
    Name                           = local.role_name
    Project                        = var.prefix
    "ahara:truenas-roles-anywhere" = "true"
    "ahara:workload-id"            = local.workload_id
  })
}

data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "entry_role_arn" {
  name = "/ahara/truenas-roles-anywhere/entry-role-arn"
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_ssm_parameter.entry_role_arn.value]
    }
    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/x509SAN/URI"
      values   = [local.workload_id]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = local.role_name
  path                 = "/${var.prefix}/truenas/"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = local.permissions_boundary_arn
  tags                 = local.tags
}

resource "aws_iam_role_policy" "runtime" {
  name   = "${local.role_name}-runtime"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}

resource "aws_ssm_parameter" "role_arn" {
  name  = "/ahara/truenas-roles-anywhere/workloads/${var.prefix}/${var.name}/role-arn"
  type  = "String"
  value = aws_iam_role.this.arn
  tags  = local.tags
}
