resource "aws_secretsmanager_secret" "wg_keys" {
  name                    = "${local.prefix}-wg-keys"
  description             = "WireGuard server keypair (private, public)"
  kms_key_id              = null # or your KMS key ARN
  recovery_window_in_days = 0
}

data "aws_iam_policy_document" "secret_res_policy" {
  statement {
    sid = "AllowAccountRootForAdmin"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["secretsmanager:*"]
    resources = [aws_secretsmanager_secret.wg_keys.arn]
  }

  statement {
    sid = "AllowWGRoleReadUpdate"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.wireguard.arn]
    }
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:PutSecretValue"
    ]
    resources = [aws_secretsmanager_secret.wg_keys.arn]
  }
}

resource "aws_secretsmanager_secret_policy" "wg_keys_policy" {
  secret_arn = aws_secretsmanager_secret.wg_keys.arn
  policy     = data.aws_iam_policy_document.secret_res_policy.json
}