# =============================================================================
# Machine identity anchored on the LAN
#
# The trust appliance (the ahara-trust repository) runs the certificate
# authority. AWS is told to trust it and nothing more: no CA private key lives
# in this state, no enrollment service runs here, and no single-use tokens are
# minted. A device presents a certificate that appliance issued and receives
# credentials scoped by its own role.
#
# Registering an appliance is committing its CA certificate — public material,
# copied from `curl https://trust.local.ahara.io:8443/ca.pem` — to
# control/ahara-machines-ca.pem and applying. That is the one manual step in
# the design, and it recurs only when the authority is rebuilt, not per device.
#
# Until that file exists nothing here is created, so the control plane applies
# cleanly before the appliance is built.
# =============================================================================

data "aws_partition" "current" {}

locals {
  ahara_machines_ca_path = "${path.module}/ahara-machines-ca.pem"
  ahara_machines_ca_pem = (
    fileexists(local.ahara_machines_ca_path) ? file(local.ahara_machines_ca_path) : ""
  )
  ahara_machines_enabled = local.ahara_machines_ca_pem != ""
  ahara_machines_count   = local.ahara_machines_enabled ? 1 : 0
}

resource "aws_rolesanywhere_trust_anchor" "ahara_machines" {
  count = local.ahara_machines_count

  name    = "ahara-machines"
  enabled = true

  source {
    source_type = "CERTIFICATE_BUNDLE"
    source_data {
      x509_certificate_data = local.ahara_machines_ca_pem
    }
  }

  tags = {
    Name = "ahara-machines"
  }
}

# Roles Anywhere assumes this role, which in turn may assume a workload role
# whose tag matches the identity in the presented certificate. That
# indirection is what stops one machine's certificate being usable as another.
data "aws_iam_policy_document" "ahara_machines_entry_assume" {
  count = local.ahara_machines_count

  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["rolesanywhere.amazonaws.com"]
    }
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity",
    ]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_rolesanywhere_trust_anchor.ahara_machines[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "ahara_machines_entry" {
  count = local.ahara_machines_count

  name               = "ahara-machines-entry"
  assume_role_policy = data.aws_iam_policy_document.ahara_machines_entry_assume[0].json

  tags = {
    Name = "ahara-machines-entry"
  }
}

resource "aws_iam_role_policy" "ahara_machines_entry" {
  count = local.ahara_machines_count

  name = "ahara-machines-entry"
  role = aws_iam_role.ahara_machines_entry[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeMatchingMachineRoles"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
          "sts:SetSourceIdentity",
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/ahara-machine-*"
        ]
        # The certificate's URI SAN becomes a principal tag and the role
        # carries the same value as a resource tag, so a certificate for one
        # machine assumes that machine's role and no other.
        Condition = {
          StringEquals = {
            "aws:ResourceTag/ahara:machine-identity" = "true"
            "aws:ResourceTag/ahara:workload-id"      = "$${aws:PrincipalTag/x509SAN/URI}"
          }
        }
      }
    ]
  })
}

resource "aws_rolesanywhere_profile" "ahara_machines" {
  count = local.ahara_machines_count

  name                     = "ahara-machines"
  enabled                  = true
  accept_role_session_name = true
  # An hour. The certificate is the long-lived credential; the session
  # deliberately is not.
  duration_seconds = 3600
  role_arns        = [aws_iam_role.ahara_machines_entry[0].arn]

  tags = {
    Name = "ahara-machines"
  }
}

# What an appliance needs to exchange its certificate for credentials. All
# three are public identifiers, so they are published rather than handed over.
resource "aws_ssm_parameter" "ahara_machines_trust_anchor_arn" {
  count = local.ahara_machines_count

  name  = "/ahara/machines/trust-anchor-arn"
  type  = "String"
  value = aws_rolesanywhere_trust_anchor.ahara_machines[0].arn
}

resource "aws_ssm_parameter" "ahara_machines_profile_arn" {
  count = local.ahara_machines_count

  name  = "/ahara/machines/profile-arn"
  type  = "String"
  value = aws_rolesanywhere_profile.ahara_machines[0].arn
}

resource "aws_ssm_parameter" "ahara_machines_entry_role_arn" {
  count = local.ahara_machines_count

  name  = "/ahara/machines/entry-role-arn"
  type  = "String"
  value = aws_iam_role.ahara_machines_entry[0].arn
}

# -----------------------------------------------------------------------------
# The trust appliance's own role
#
# It runs the household's only ACME client, so it is the only machine that
# needs to answer a DNS-01 challenge. The role lives here rather than in the
# appliance's own Terraform because the appliance's deploy path must not be
# able to widen what the appliance may do.
#
# The identity it presents is one it minted for itself — it holds the CA key,
# so an enrollment round trip would prove nothing. What that identity is worth
# is decided entirely here.
# -----------------------------------------------------------------------------

# The same zone the network layer serves the public names from. The challenge
# record for *.local.ahara.io is written here, because that subtree is
# authoritative only on the LAN and Let's Encrypt cannot see it.
data "aws_route53_zone" "root" {
  count = local.ahara_machines_count

  name         = "ahara.io."
  private_zone = false
}

data "aws_iam_policy_document" "ahara_trust_route53" {
  count = local.ahara_machines_count

  # Answering DNS-01 means writing and removing one TXT record per order.
  # Scoped to the zone that holds the household's names; no other zone and no
  # zone administration.
  statement {
    sid    = "AnswerDnsChallenges"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/${data.aws_route53_zone.root[0].zone_id}"]
  }

  # lego resolves the zone for a name before it writes, and both of these are
  # account-wide reads with no resource form.
  statement {
    sid    = "FindTheZone"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:GetChange",
    ]
    resources = ["*"]
  }
}

module "ahara_trust_machine_role" {
  count  = local.ahara_machines_count
  source = "../modules/machine-role"

  prefix      = "appliance"
  name        = "trust"
  policy_json = data.aws_iam_policy_document.ahara_trust_route53[0].json

  # This apply creates the entry role, so its ARN is passed rather than read
  # back from the parameter the module would otherwise look up — that
  # parameter does not exist yet on a first apply.
  entry_role_arn               = aws_iam_role.ahara_machines_entry[0].arn
  read_entry_role_arn_from_ssm = false
}
