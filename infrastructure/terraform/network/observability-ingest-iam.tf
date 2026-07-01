# =============================================================================
# Allow the Alloy hosts to read the observability ingest credentials from SSM.
#
# Every Alloy agent (reverse proxy, NAT, WireGuard) pushes logs to TrueNAS Loki
# — and the reverse proxy also remote-writes metrics and exports OTLP traces —
# so each needs the Cognito M2M client_credentials fetched at boot. The client
# secret is a SecureString, so kms:Decrypt (scoped to SSM) is also required.
# =============================================================================

data "aws_region" "current" {}

data "aws_iam_policy_document" "observability_ingest_read" {
  statement {
    sid       = "ReadIngestCreds"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:*:*:parameter/${local.prefix}/observability/ingest-*"]
  }

  statement {
    sid       = "DecryptIngestSecret"
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

resource "aws_iam_role_policy" "reverse_proxy_ingest_read" {
  name   = "${local.prefix}-observability-ingest-read"
  role   = aws_iam_role.reverse_proxy.name
  policy = data.aws_iam_policy_document.observability_ingest_read.json
}

resource "aws_iam_role_policy" "nat_ingest_read" {
  name   = "${local.prefix}-observability-ingest-read"
  role   = aws_iam_role.nat.name
  policy = data.aws_iam_policy_document.observability_ingest_read.json
}

resource "aws_iam_role_policy" "wireguard_ingest_read" {
  name   = "${local.prefix}-observability-ingest-read"
  role   = aws_iam_role.wireguard.name
  policy = data.aws_iam_policy_document.observability_ingest_read.json
}
