locals {
  security_log_bucket_arn        = "arn:aws:s3:::${var.prefix}-security-logs-*"
  security_log_bucket_object_arn = "arn:aws:s3:::${var.prefix}-security-logs-*/*"
}

data "aws_iam_policy_document" "this" {
  statement {
    sid    = "SecurityLogBucketCreate"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SecurityLogBucketManage"
    effect = "Allow"
    actions = [
      "s3:DeleteBucket",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketAcl",
      "s3:GetBucketLocation",
      "s3:GetBucketLogging",
      "s3:GetBucketOwnershipControls",
      "s3:GetBucketPolicy",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:DeleteBucketPolicy",
      "s3:DeleteBucketOwnershipControls",
      "s3:DeleteBucketPublicAccessBlock",
      "s3:DeleteBucketEncryption",
      "s3:DeleteLifecycleConfiguration",
      "s3:PutBucketAcl",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
    ]
    resources = [local.security_log_bucket_arn]
  }

  statement {
    sid    = "SecurityLogObjectsManage"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
    ]
    resources = [local.security_log_bucket_object_arn]
  }

  statement {
    sid    = "CloudTrailManage"
    effect = "Allow"
    actions = [
      "cloudtrail:AddTags",
      "cloudtrail:CreateTrail",
      "cloudtrail:DeleteTrail",
      "cloudtrail:GetEventSelectors",
      "cloudtrail:GetInsightSelectors",
      "cloudtrail:GetTrail",
      "cloudtrail:ListTags",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:PutInsightSelectors",
      "cloudtrail:RemoveTags",
      "cloudtrail:StartLogging",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
    ]
    resources = ["arn:aws:cloudtrail:*:${var.account_id}:trail/${var.prefix}-*"]
  }

  statement {
    sid    = "GuardDutyManage"
    effect = "Allow"
    actions = [
      "guardduty:CreateDetector",
      "guardduty:DeleteDetector",
      "guardduty:GetDetector",
      "guardduty:TagResource",
      "guardduty:UntagResource",
      "guardduty:UpdateDetector",
    ]
    resources = [
      "arn:aws:guardduty:*:${var.account_id}:detector/*",
    ]
  }

  statement {
    sid    = "SecurityHubCspmManage"
    effect = "Allow"
    actions = [
      "securityhub:BatchDisableStandards",
      "securityhub:BatchEnableStandards",
      "securityhub:DisableSecurityHub",
      "securityhub:EnableSecurityHub",
      "securityhub:GetEnabledStandards",
      "securityhub:GetSecurityHubV2Configuration",
      "securityhub:TagResource",
      "securityhub:UntagResource",
      "securityhub:UpdateSecurityHubConfiguration",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AccessAnalyzerManage"
    effect = "Allow"
    actions = [
      "access-analyzer:CreateAnalyzer",
      "access-analyzer:DeleteAnalyzer",
      "access-analyzer:GetAnalyzer",
      "access-analyzer:TagResource",
      "access-analyzer:UntagResource",
      "access-analyzer:UpdateAnalyzer",
    ]
    resources = [
      "arn:aws:access-analyzer:*:${var.account_id}:analyzer/${var.prefix}-*",
    ]
  }

  statement {
    sid    = "VpcFlowLogsManage"
    effect = "Allow"
    actions = [
      "ec2:CreateFlowLogs",
      "ec2:CreateTags",
      "ec2:DeleteFlowLogs",
      "ec2:DescribeFlowLogs",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Route53ResolverQueryLogsManage"
    effect = "Allow"
    actions = [
      "route53resolver:AssociateResolverQueryLogConfig",
      "route53resolver:CreateResolverQueryLogConfig",
      "route53resolver:DeleteResolverQueryLogConfig",
      "route53resolver:DisassociateResolverQueryLogConfig",
      "route53resolver:GetResolverQueryLogConfig",
      "route53resolver:GetResolverQueryLogConfigAssociation",
      "route53resolver:ListResolverQueryLogConfigAssociations",
      "route53resolver:ListResolverQueryLogConfigs",
      "route53resolver:TagResource",
      "route53resolver:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "WafLoggingManage"
    effect = "Allow"
    actions = [
      "wafv2:DeleteLoggingConfiguration",
      "wafv2:GetLoggingConfiguration",
      "wafv2:PutLoggingConfiguration",
    ]
    resources = [
      "arn:aws:wafv2:*:${var.account_id}:regional/webacl/${var.prefix}-*/*",
      "arn:aws:wafv2:us-east-1:${var.account_id}:global/webacl/${var.prefix}-*/*",
    ]
  }

  statement {
    sid    = "CloudWatchLogDeliveryManage"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:CreateLogGroup",
      "logs:DeleteLogDelivery",
      "logs:DeleteLogGroup",
      "logs:DeleteResourcePolicy",
      "logs:DescribeLogGroups",
      "logs:DescribeLogDeliveries",
      "logs:DescribeResourcePolicies",
      "logs:GetLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:UpdateLogDelivery",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CreateSecurityServiceLinkedRoles"
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["arn:aws:iam::${var.account_id}:role/aws-service-role/*"]

    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values = [
        "access-analyzer.amazonaws.com",
        "guardduty.amazonaws.com",
        "securityhub.amazonaws.com",
      ]
    }
  }
}
