data "aws_partition" "current" {}

locals {
  truenas_roles_anywhere_prefix             = "/ahara/truenas-roles-anywhere"
  truenas_roles_anywhere_cert_validity_days = 90
}

resource "aws_acmpca_certificate_authority" "truenas_workloads" {
  type                            = "ROOT"
  permanent_deletion_time_in_days = 7

  certificate_authority_configuration {
    key_algorithm     = "RSA_4096"
    signing_algorithm = "SHA512WITHRSA"

    subject {
      common_name         = "ahara-truenas-workloads"
      organization        = "Ahara"
      organizational_unit = "TrueNAS"
    }
  }

  tags = {
    Name = "ahara-truenas-workloads"
  }
}

resource "aws_acmpca_certificate" "truenas_workloads_ca" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.truenas_workloads.arn
  certificate_signing_request = aws_acmpca_certificate_authority.truenas_workloads.certificate_signing_request
  signing_algorithm           = "SHA512WITHRSA"
  template_arn                = "arn:${data.aws_partition.current.partition}:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

resource "aws_acmpca_certificate_authority_certificate" "truenas_workloads" {
  certificate_authority_arn = aws_acmpca_certificate_authority.truenas_workloads.arn
  certificate               = aws_acmpca_certificate.truenas_workloads_ca.certificate
  certificate_chain         = aws_acmpca_certificate.truenas_workloads_ca.certificate_chain
}

resource "aws_rolesanywhere_trust_anchor" "truenas_workloads" {
  name    = "ahara-truenas-workloads"
  enabled = true

  source {
    source_type = "AWS_ACM_PCA"
    source_data {
      acm_pca_arn = aws_acmpca_certificate_authority.truenas_workloads.arn
    }
  }

  tags = {
    Name = "ahara-truenas-workloads"
  }

  depends_on = [aws_acmpca_certificate_authority_certificate.truenas_workloads]
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
        Action = "sts:AssumeRole"
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
        Sid    = "IssueWorkloadCertificates"
        Effect = "Allow"
        Action = [
          "acm-pca:IssueCertificate",
          "acm-pca:GetCertificate"
        ]
        Resource = [
          aws_acmpca_certificate_authority.truenas_workloads.arn,
          "${aws_acmpca_certificate_authority.truenas_workloads.arn}/certificate/*"
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
      AWS_PARTITION      = data.aws_partition.current.partition
      CA_ARN             = aws_acmpca_certificate_authority.truenas_workloads.arn
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

resource "aws_ssm_parameter" "truenas_roles_anywhere_ca_arn" {
  name  = "${local.truenas_roles_anywhere_prefix}/ca-arn"
  type  = "String"
  value = aws_acmpca_certificate_authority.truenas_workloads.arn
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
