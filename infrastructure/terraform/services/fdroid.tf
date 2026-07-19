locals {
  fdroid_hostname    = "fdroid.${local.services_domain}"
  fdroid_bucket_name = "airwave-fdroid-${data.aws_caller_identity.current.account_id}"
  fdroid_keys_bucket = "airwave-fdroid-keys-${data.aws_caller_identity.current.account_id}"
}

# Private bucket for the persistent APK + repo signing keystores. Never fronted
# by CloudFront, so the keys are not publicly reachable. The airwave deployer
# role reaches it via the s3-private-storage policy (airwave-* namespace).
resource "aws_s3_bucket" "fdroid_keys" {
  bucket = local.fdroid_keys_bucket
}

resource "aws_s3_bucket_public_access_block" "fdroid_keys" {
  bucket = aws_s3_bucket.fdroid_keys.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "fdroid_keys" {
  bucket = aws_s3_bucket.fdroid_keys.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "fdroid_keys" {
  bucket = aws_s3_bucket.fdroid_keys.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "fdroid" {
  bucket = local.fdroid_bucket_name
}

resource "aws_s3_bucket_public_access_block" "fdroid" {
  bucket = aws_s3_bucket.fdroid.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "fdroid" {
  bucket = aws_s3_bucket.fdroid.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "fdroid" {
  bucket = aws_s3_bucket.fdroid.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_cloudfront_origin_access_control" "fdroid" {
  name                              = "${local.prefix}-fdroid-oac"
  description                       = "Access airwave F-Droid repository bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "fdroid_bucket" {
  statement {
    sid     = "AllowCloudFrontRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.fdroid.arn}/*",
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.fdroid.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "fdroid" {
  bucket = aws_s3_bucket.fdroid.id
  policy = data.aws_iam_policy_document.fdroid_bucket.json
}

resource "aws_acm_certificate" "fdroid" {
  domain_name       = local.fdroid_hostname
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "fdroid_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.fdroid.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "fdroid" {
  certificate_arn         = aws_acm_certificate.fdroid.arn
  validation_record_fqdns = [for r in aws_route53_record.fdroid_cert_validation : r.fqdn]
}

resource "aws_cloudfront_distribution" "fdroid" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Airwave F-Droid repository"
  aliases         = [local.fdroid_hostname]
  price_class     = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.fdroid.bucket_regional_domain_name
    origin_id                = "s3-fdroid"
    origin_access_control_id = aws_cloudfront_origin_access_control.fdroid.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-fdroid"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    default_ttl            = 300
    min_ttl                = 0
    max_ttl                = 300

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.fdroid.certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }
}

resource "aws_route53_record" "fdroid_a" {
  zone_id = var.route53_zone_id
  name    = local.fdroid_hostname
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.fdroid.domain_name
    zone_id                = aws_cloudfront_distribution.fdroid.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "fdroid_aaaa" {
  zone_id = var.route53_zone_id
  name    = local.fdroid_hostname
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.fdroid.domain_name
    zone_id                = aws_cloudfront_distribution.fdroid.hosted_zone_id
    evaluate_target_health = false
  }
}
