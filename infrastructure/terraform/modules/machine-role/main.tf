# An AWS role a machine may assume by presenting an identity the trust
# appliance issued.
#
# The binding is two-sided and both sides must agree or nothing is assumable:
# the entry role may only reach roles named ahara-machine-* whose
# ahara:workload-id tag equals the URI SAN in the presented certificate, and
# this role's own trust policy independently pins the same value. A
# certificate for one machine is therefore useless against another's role.
#
# No credential is created here. The machine holds a certificate, not a key.

variable "prefix" {
  description = "Project or estate the workload belongs to."
  type        = string
}

variable "name" {
  description = "Workload name, unique within the prefix."
  type        = string
}

variable "policy_json" {
  description = "What this machine may do once it has credentials."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "Optional boundary capping what the runtime policy can grant."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}

data "aws_ssm_parameter" "entry_role_arn" {
  name = "/ahara/machines/entry-role-arn"
}

locals {
  role_name   = "ahara-machine-${var.prefix}-${var.name}"
  workload_id = "spiffe://ahara/${var.prefix}/${var.name}"

  tags = merge(var.tags, {
    Name                     = local.role_name
    Project                  = var.prefix
    "ahara:machine-identity" = "true"
    "ahara:workload-id"      = local.workload_id
  })
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [data.aws_ssm_parameter.entry_role_arn.value]
    }
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/x509SAN/URI"
      values   = [local.workload_id]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = local.role_name
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = local.tags
}

resource "aws_iam_role_policy" "runtime" {
  name   = "${local.role_name}-runtime"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}

# Read by the deploy tooling so a workload learns which role to assume
# without the name being written down twice.
resource "aws_ssm_parameter" "role_arn" {
  name  = "/ahara/machines/workloads/${var.prefix}/${var.name}/role-arn"
  type  = "String"
  value = aws_iam_role.this.arn
  tags  = local.tags
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "workload_id" {
  value = local.workload_id
}
