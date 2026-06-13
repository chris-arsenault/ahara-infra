locals {
  ses_identity_namespace_arn          = "arn:aws:ses:*:${var.account_id}:identity/${var.prefix}-*"
  ses_configuration_set_namespace_arn = "arn:aws:ses:*:${var.account_id}:configuration-set/${var.prefix}-*"
  additional_ses_identity_arns = [
    for domain in var.additional_ses_identity_domains :
    "arn:aws:ses:*:${var.account_id}:identity/${domain}"
  ]
  ses_identity_arns = concat([local.ses_identity_namespace_arn], local.additional_ses_identity_arns)
}

data "aws_iam_policy_document" "this" {
  # SES receipt rules and rule sets do not expose resource ARNs in IAM, so
  # receipt-rule management must use "*". Keep identity and send actions
  # scoped below where SES supports resource-level permissions.
  statement {
    sid    = "SesManagement"
    effect = "Allow"
    actions = [
      "ses:CloneReceiptRuleSet",
      "ses:CreateConfigurationSet",
      "ses:CreateConfigurationSetEventDestination",
      "ses:CreateReceiptRule",
      "ses:CreateReceiptRuleSet",
      "ses:DeleteConfigurationSet",
      "ses:DeleteConfigurationSetEventDestination",
      "ses:DeleteReceiptRule",
      "ses:DeleteReceiptRuleSet",
      "ses:DescribeActiveReceiptRuleSet",
      "ses:DescribeConfigurationSet",
      "ses:DescribeReceiptRule",
      "ses:DescribeReceiptRuleSet",
      "ses:GetIdentityDkimAttributes",
      "ses:GetIdentityMailFromDomainAttributes",
      "ses:GetIdentityNotificationAttributes",
      "ses:GetIdentityPolicies",
      "ses:GetIdentityVerificationAttributes",
      "ses:ListConfigurationSets",
      "ses:ListIdentities",
      "ses:ListIdentityPolicies",
      "ses:ListReceiptRuleSets",
      "ses:ListVerifiedEmailAddresses",
      "ses:PutConfigurationSetDeliveryOptions",
      "ses:ReorderReceiptRuleSet",
      "ses:SetActiveReceiptRuleSet",
      "ses:SetIdentityDkimEnabled",
      "ses:SetIdentityFeedbackForwardingEnabled",
      "ses:SetIdentityHeadersInNotificationsEnabled",
      "ses:SetIdentityMailFromDomain",
      "ses:SetIdentityNotificationTopic",
      "ses:SetReceiptRulePosition",
      "ses:UpdateConfigurationSetEventDestination",
      "ses:UpdateConfigurationSetReputationMetricsEnabled",
      "ses:UpdateConfigurationSetSendingEnabled",
      "ses:UpdateReceiptRule",
      "ses:VerifyDomainDkim",
      "ses:VerifyDomainIdentity",
      "ses:VerifyEmailIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SesIdentityPermissions"
    effect = "Allow"
    actions = [
      "ses:DeleteIdentity",
      "ses:DeleteIdentityPolicy",
      "ses:PutIdentityPolicy",
    ]
    resources = local.ses_identity_arns
  }

  statement {
    sid    = "SesIdentityList"
    effect = "Allow"
    actions = [
      "ses:GetAccountSendingEnabled",
      "ses:GetSendQuota",
      "ses:GetSendStatistics",
      "ses:ListIdentities",
      "ses:ListVerifiedEmailAddresses",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SesSendFromProjectIdentities"
    effect = "Allow"
    actions = [
      "ses:SendBounce",
      "ses:SendEmail",
      "ses:SendRawEmail",
    ]
    resources = local.ses_identity_arns
  }

  statement {
    sid    = "SesSendWithProjectConfigurationSets"
    effect = "Allow"
    actions = [
      "ses:SendBulkTemplatedEmail",
      "ses:SendEmail",
      "ses:SendRawEmail",
      "ses:SendTemplatedEmail",
    ]
    resources = [local.ses_configuration_set_namespace_arn]
  }
}
