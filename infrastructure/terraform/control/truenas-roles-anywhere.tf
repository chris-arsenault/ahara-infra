data "aws_partition" "current" {}

locals {
  truenas_roles_anywhere_prefix             = "/ahara/truenas-roles-anywhere"
  truenas_roles_anywhere_cert_validity_days = 90
}

# Self-managed CA. The previous design used AWS Private CA, which carries a
# ~$400/month fixed charge; Roles Anywhere itself is free and accepts any
# X.509 root via a CERTIFICATE_BUNDLE trust anchor. The CA private key lives
# in Terraform state and an SSM SecureString — weaker custody than an HSM,
# accepted trade-off for this account. The enrollment Lambda signs workload
# CSRs with this key.
resource "tls_private_key" "truenas_workloads_ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "truenas_workloads_ca" {
  private_key_pem = tls_private_key.truenas_workloads_ca.private_key_pem

  subject {
    common_name         = "ahara-truenas-workloads"
    organization        = "Ahara"
    organizational_unit = "TrueNAS"
  }

  is_ca_certificate     = true
  validity_period_hours = 87600 # 10 years

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

resource "aws_ssm_parameter" "truenas_roles_anywhere_ca_key" {
  name  = "${local.truenas_roles_anywhere_prefix}/ca-key"
  type  = "SecureString"
  value = tls_private_key.truenas_workloads_ca.private_key_pem_pkcs8
}

resource "aws_ssm_parameter" "truenas_roles_anywhere_ca_cert" {
  name  = "${local.truenas_roles_anywhere_prefix}/ca-cert"
  type  = "String"
  value = tls_self_signed_cert.truenas_workloads_ca.cert_pem
}

resource "aws_rolesanywhere_trust_anchor" "truenas_workloads" {
  name    = "ahara-truenas-workloads"
  enabled = true

  source {
    source_type = "CERTIFICATE_BUNDLE"
    source_data {
      x509_certificate_data = tls_self_signed_cert.truenas_workloads_ca.cert_pem
    }
  }

  tags = {
    Name = "ahara-truenas-workloads"
  }
}

data "aws_iam_policy_document" "truenas_roles_anywhere_entry_assume" {
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
      values   = [aws_rolesanywhere_trust_anchor.truenas_workloads.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "truenas_roles_anywhere_entry" {
  name               = "ahara-truenas-rolesanywhere-entry"
  assume_role_policy = data.aws_iam_policy_document.truenas_roles_anywhere_entry_assume.json

  tags = {
    Name = "ahara-truenas-rolesanywhere-entry"
  }
}

resource "aws_iam_role_policy" "truenas_roles_anywhere_entry" {
  name = "ahara-truenas-rolesanywhere-entry"
  role = aws_iam_role.truenas_roles_anywhere_entry.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeMatchingTrueNasWorkloadRoles"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
          "sts:SetSourceIdentity",
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/*-truenas-*",
          "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/*/truenas/*-truenas-*"
        ]
        Condition = {
          StringEquals = {
            "aws:ResourceTag/ahara:truenas-roles-anywhere" = "true"
            "aws:ResourceTag/ahara:workload-id"            = "$${aws:PrincipalTag/x509SAN/URI}"
          }
        }
      }
    ]
  })
}

resource "aws_rolesanywhere_profile" "truenas_workloads" {
  name                     = "ahara-truenas-workloads"
  enabled                  = true
  accept_role_session_name = true
  duration_seconds         = 3600
  role_arns                = [aws_iam_role.truenas_roles_anywhere_entry.arn]

  tags = {
    Name = "ahara-truenas-workloads"
  }
}

data "archive_file" "truenas_roles_anywhere_enroll" {
  type        = "zip"
  source_file = "${path.module}/../../../backend/target/lambda/truenas-roles-anywhere-enroll/bootstrap"
  output_path = "${path.module}/truenas-roles-anywhere-enroll-lambda.zip"
}

data "aws_iam_policy_document" "truenas_roles_anywhere_enroll_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "truenas_roles_anywhere_enroll" {
  name               = "ahara-truenas-rolesanywhere-enroll"
  assume_role_policy = data.aws_iam_policy_document.truenas_roles_anywhere_enroll_assume.json
}

resource "aws_iam_role_policy_attachment" "truenas_roles_anywhere_enroll_basic" {
  role       = aws_iam_role.truenas_roles_anywhere_enroll.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "truenas_roles_anywhere_enroll" {
  name = "ahara-truenas-rolesanywhere-enroll"
  role = aws_iam_role.truenas_roles_anywhere_enroll.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadCaMaterial"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:ssm:*:${local.account_id}:parameter/ahara/truenas-roles-anywhere/ca-key",
          "arn:${data.aws_partition.current.partition}:ssm:*:${local.account_id}:parameter/ahara/truenas-roles-anywhere/ca-cert"
        ]
      },
      {
        Sid    = "ReadWorkloadRegistrations"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:ssm:*:${local.account_id}:parameter/ahara/truenas-roles-anywhere/workloads/*"
        ]
      },
      {
        Sid    = "ConsumeEnrollmentTokens"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:DeleteParameter"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:ssm:*:${local.account_id}:parameter/ahara/truenas-roles-anywhere/enrollment/*"
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "truenas_roles_anywhere_enroll" {
  function_name = "ahara-truenas-rolesanywhere-enroll"
  role          = aws_iam_role.truenas_roles_anywhere_enroll.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"

  filename         = data.archive_file.truenas_roles_anywhere_enroll.output_path
  source_code_hash = data.archive_file.truenas_roles_anywhere_enroll.output_base64sha256

  timeout     = 30
  memory_size = 128

  environment {
    variables = {
      CA_CERT_PARAM      = aws_ssm_parameter.truenas_roles_anywhere_ca_cert.name
      CA_KEY_PARAM       = aws_ssm_parameter.truenas_roles_anywhere_ca_key.name
      CERT_VALIDITY_DAYS = tostring(local.truenas_roles_anywhere_cert_validity_days)
      ENTRY_ROLE_ARN     = aws_iam_role.truenas_roles_anywhere_entry.arn
      PROFILE_ARN        = aws_rolesanywhere_profile.truenas_workloads.arn
      TRUST_ANCHOR_ARN   = aws_rolesanywhere_trust_anchor.truenas_workloads.arn
    }
  }
}

resource "aws_lambda_function_url" "truenas_roles_anywhere_enroll" {
  function_name      = aws_lambda_function.truenas_roles_anywhere_enroll.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "truenas_roles_anywhere_enroll_url" {
  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.truenas_roles_anywhere_enroll.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_ssm_parameter" "truenas_roles_anywhere_trust_anchor_arn" {
  name  = "${local.truenas_roles_anywhere_prefix}/trust-anchor-arn"
  type  = "String"
  value = aws_rolesanywhere_trust_anchor.truenas_workloads.arn
}

resource "aws_ssm_parameter" "truenas_roles_anywhere_profile_arn" {
  name  = "${local.truenas_roles_anywhere_prefix}/profile-arn"
  type  = "String"
  value = aws_rolesanywhere_profile.truenas_workloads.arn
}

resource "aws_ssm_parameter" "truenas_roles_anywhere_entry_role_arn" {
  name  = "${local.truenas_roles_anywhere_prefix}/entry-role-arn"
  type  = "String"
  value = aws_iam_role.truenas_roles_anywhere_entry.arn
}

resource "aws_ssm_parameter" "truenas_roles_anywhere_enrollment_url" {
  name  = "${local.truenas_roles_anywhere_prefix}/enrollment-url"
  type  = "String"
  value = aws_lambda_function_url.truenas_roles_anywhere_enroll.function_url
}

resource "aws_ssm_parameter" "truenas_roles_anywhere_cert_validity_days" {
  name  = "${local.truenas_roles_anywhere_prefix}/cert-validity-days"
  type  = "String"
  value = tostring(local.truenas_roles_anywhere_cert_validity_days)
}
