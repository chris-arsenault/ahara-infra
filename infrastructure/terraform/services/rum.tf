resource "aws_cognito_identity_pool" "rum" {
  identity_pool_name               = "${local.prefix}-rum"
  allow_unauthenticated_identities = true

  tags = {
    Service = "browser-rum"
  }
}

data "aws_iam_policy_document" "rum_unauthenticated_assume_role" {
  statement {
    sid     = "AllowCognitoRumIdentityPool"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.rum.id]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["unauthenticated"]
    }
  }
}

resource "aws_iam_role" "rum_unauthenticated" {
  name               = "${local.prefix}-rum-unauthenticated"
  assume_role_policy = data.aws_iam_policy_document.rum_unauthenticated_assume_role.json

  tags = {
    Service = "browser-rum"
  }
}

resource "aws_cognito_identity_pool_roles_attachment" "rum" {
  identity_pool_id = aws_cognito_identity_pool.rum.id

  roles = {
    unauthenticated = aws_iam_role.rum_unauthenticated.arn
  }
}

data "aws_iam_policy_document" "rum_put_events" {
  statement {
    sid     = "AllowPutRumEvents"
    effect  = "Allow"
    actions = ["rum:PutRumEvents"]
    resources = [
      "arn:aws:rum:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:appmonitor/*",
    ]
  }
}

resource "aws_iam_role_policy" "rum_put_events" {
  name   = "${local.prefix}-rum-put-events"
  role   = aws_iam_role.rum_unauthenticated.id
  policy = data.aws_iam_policy_document.rum_put_events.json
}

resource "aws_ssm_parameter" "rum_identity_pool_id" {
  name  = "${local.ssm_prefix}/rum/identity-pool-id"
  type  = "String"
  value = aws_cognito_identity_pool.rum.id
}

resource "aws_ssm_parameter" "rum_guest_role_arn" {
  name  = "${local.ssm_prefix}/rum/guest-role-arn"
  type  = "String"
  value = aws_iam_role.rum_unauthenticated.arn
}
