resource "aws_cloudtrail" "account" {
  name                          = local.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.security_logs.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  enable_logging                = true

  advanced_event_selector {
    name = "Management events"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  advanced_event_selector {
    name = "Sensitive S3 object events"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }

    field_selector {
      field = "resources.ARN"
      starts_with = [
        "${aws_s3_bucket.security_logs.arn}/",
        "arn:aws:s3:::${local.prefix}-migrations-${data.aws_caller_identity.current.account_id}/",
      ]
    }
  }

  advanced_event_selector {
    name = "Ahara Lambda invoke events"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::Lambda::Function"]
    }

    field_selector {
      field       = "resources.ARN"
      starts_with = ["arn:aws:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:${local.prefix}-"]
    }
  }

  insight_selector {
    insight_type = "ApiCallRateInsight"
  }

  insight_selector {
    insight_type = "ApiErrorRateInsight"
  }

  depends_on = [aws_s3_bucket_policy.security_logs]
}

resource "aws_guardduty_detector" "account" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

locals {
  guardduty_feature_names = toset([
    "S3_DATA_EVENTS",
    "LAMBDA_NETWORK_LOGS",
    "RDS_LOGIN_EVENTS",
    "EBS_MALWARE_PROTECTION",
  ])
}

resource "aws_guardduty_detector_feature" "account" {
  for_each    = local.guardduty_feature_names
  detector_id = aws_guardduty_detector.account.id
  name        = each.value
  status      = "ENABLED"
}

resource "aws_securityhub_account" "cspm" {
  enable_default_standards  = false
  auto_enable_controls      = true
  control_finding_generator = "SECURITY_CONTROL"
}

resource "aws_securityhub_standards_subscription" "foundational" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.region}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.cspm]
}

resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "${local.prefix}-external-access"
  type          = "ACCOUNT"
}
