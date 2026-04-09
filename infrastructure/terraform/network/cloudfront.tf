data "aws_cloudfront_cache_policy" "cache_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

resource "aws_cloudfront_distribution" "reverse_proxy" {
  enabled             = true
  comment             = "Reverse proxy for home services"
  default_root_object = ""

  aliases = local.reverse_proxy_hostnames

  origin {
    domain_name = aws_lb.reverse_proxy.dns_name
    origin_id   = "alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb-origin"

    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.cache_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id

    compress = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.reverse_proxy.certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  depends_on = [aws_acm_certificate_validation.reverse_proxy]
}

resource "aws_route53_record" "reverse_proxy_alias_a" {
  for_each = toset(local.reverse_proxy_hostnames)

  zone_id = local.route53_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.reverse_proxy.domain_name
    zone_id                = aws_cloudfront_distribution.reverse_proxy.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "reverse_proxy_alias_aaaa" {
  for_each = toset(local.reverse_proxy_hostnames)

  zone_id = local.route53_zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.reverse_proxy.domain_name
    zone_id                = aws_cloudfront_distribution.reverse_proxy.hosted_zone_id
    evaluate_target_health = false
  }
}
