# =============================================================================
# Where the trust appliance's stored secrets survive losing the appliance
#
# The appliance holds secrets that have no home in AWS — an SSH private key for
# a host outside this estate, most often. Unlike its certificate authority and
# the identities it issues, those cannot be regenerated: re-enrollment recovers
# an identity, and nothing recovers a key somebody else issued. They are
# therefore backed up, which the appliance's own rules otherwise forbid
# (ahara-trust ADR-0003).
#
# Encryption is the bucket's own SSE-KMS under the key below: a data key per
# object, wrapped by KMS, stored beside the ciphertext. The appliance uploads
# with no encryption flags and needs no encryption code.
#
# The appliance may both write and read. A rebuild is a deliberate session at
# a console, and a restore it cannot perform itself would be a recovery share
# by another name.
# =============================================================================

# Untagged, because the role that applies this stack may create a key but not
# tag one, and widening that grant to carry a Name the alias below already
# supplies would be a poor trade.
resource "aws_kms_key" "ahara_trust_secrets" {
  count = local.ahara_machines_count

  description             = "Wraps the trust appliance's stored secrets in S3"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "ahara_trust_secrets" {
  count = local.ahara_machines_count

  name          = "alias/ahara-trust-secrets"
  target_key_id = aws_kms_key.ahara_trust_secrets[0].key_id
}

resource "aws_s3_bucket" "ahara_trust_secrets" {
  count = local.ahara_machines_count

  bucket = "ahara-trust-secrets-${local.account_id}"

  tags = {
    Name = "ahara-trust-secrets"
  }
}

# The store is one object overwritten on every change, so history lives here
# rather than on the appliance. It is the only way back from a secret that was
# replaced with the wrong value.
resource "aws_s3_bucket_versioning" "ahara_trust_secrets" {
  count = local.ahara_machines_count

  bucket = aws_s3_bucket.ahara_trust_secrets[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ahara_trust_secrets" {
  count = local.ahara_machines_count

  bucket = aws_s3_bucket.ahara_trust_secrets[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.ahara_trust_secrets[0].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "ahara_trust_secrets" {
  count = local.ahara_machines_count

  bucket                  = aws_s3_bucket.ahara_trust_secrets[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "ahara_trust_secret_backup" {
  count = local.ahara_machines_count

  statement {
    sid    = "KeepTheSecretStore"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
    ]
    resources = ["${aws_s3_bucket.ahara_trust_secrets[0].arn}/*"]
  }

  # `aws s3 cp` heads the bucket before it writes.
  statement {
    sid       = "FindTheBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.ahara_trust_secrets[0].arn]
  }

  # S3 asks KMS on the appliance's behalf, so the appliance needs the grant
  # even though it never calls KMS itself.
  statement {
    sid    = "WrapAndUnwrapTheDataKey"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.ahara_trust_secrets[0].arn]
  }
}

# Copied into the appliance's topology.json, the way the trust anchor and
# profile ARNs already are. A bucket name is a public identifier, so the
# appliance is told where to write rather than asking AWS at runtime.
output "ahara_trust_secrets_bucket" {
  description = "Bucket holding the trust appliance's secret store backup."
  value       = local.ahara_machines_enabled ? aws_s3_bucket.ahara_trust_secrets[0].id : ""
}
