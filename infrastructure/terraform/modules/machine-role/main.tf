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
  description = "What this machine may do once it has credentials, beyond reading its own project's parameters. Unset for a workload that only reads its configuration."
  type        = string
  default     = null
}

variable "cross_project_parameter_prefixes" {
  description = "Other projects whose parameters this workload reads, as bare project names. A security decision, so it is declared where the role is."
  type        = list(string)
  default     = []
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

variable "entry_role_arn" {
  description = "The role Roles Anywhere admits an identity as. Read from SSM when unset; pass it when the same apply creates it, since the parameter does not exist yet."
  type        = string
  default     = null
}

variable "read_entry_role_arn_from_ssm" {
  description = "Whether to read the Roles Anywhere entry role ARN from SSM. Set false when entry_role_arn comes from a resource created in the same apply."
  type        = bool
  default     = true
}

data "aws_ssm_parameter" "entry_role_arn" {
  count = var.read_entry_role_arn_from_ssm ? 1 : 0

  name = "/ahara/machines/entry-role-arn"
}

locals {
  entry_role_arn = (
    var.read_entry_role_arn_from_ssm ? data.aws_ssm_parameter.entry_role_arn[0].value : var.entry_role_arn
  )

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
      identifiers = [local.entry_role_arn]
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

# One policy, always created, holding what this machine may read and whatever
# else the caller grants it.
#
# The caller's document is merged rather than attached separately, because a
# count that depends on whether it was supplied is a count Terraform cannot
# resolve: a policy built from a resource that does not exist yet — a bucket or
# a key created in the same apply — is unknown at plan time, and so is whether
# it is null. Merging keeps the conditional in an argument, where an unknown is
# allowed.
data "aws_iam_policy_document" "runtime" {
  source_policy_documents = var.policy_json == null ? [] : [var.policy_json]

  statement {
    sid    = "ReadOwnProjectParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = local.readable_parameters
  }

  # These are SecureString parameters, so reading one is also a KMS decrypt.
  # Scoped to calls SSM makes on the workload's behalf, so the grant is not
  # usable against anything else the key protects.
  statement {
    sid       = "DecryptThoseParameters"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "runtime" {
  name   = "${local.role_name}-runtime"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.runtime.json
}

# What this workload may read, derived from what it is.
#
# Parameters are already filed by project — /ahara/<project>/... and
# /ahara/truenas-db/<project>/... — and a workload id is
# spiffe://ahara/<prefix>/<name> where the prefix is that same project. So the
# namespace is the grant and nobody writes a list of parameters (ahara-trust
# ADR-0002). Reading another project's parameters is declared, because it is a
# decision rather than a consequence.
#
# The namespace being the grant makes it load-bearing: a parameter filed under
# the wrong project is readable by the wrong workloads, and nothing here will
# say so.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  parameter_arn_prefix = join(":", [
    "arn",
    data.aws_partition.current.partition,
    "ssm",
    data.aws_region.current.region,
    data.aws_caller_identity.current.account_id,
    "parameter",
  ])

  readable_parameters = concat(
    [
      "${local.parameter_arn_prefix}/ahara/${var.prefix}/*",
      "${local.parameter_arn_prefix}/ahara/truenas-db/${var.prefix}/*",
    ],
    [for p in var.cross_project_parameter_prefixes : "${local.parameter_arn_prefix}/ahara/${p}/*"],
  )
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
