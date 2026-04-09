resource "aws_acm_certificate" "reverse_proxy" {
  domain_name               = local.reverse_proxy_primary_hostname
  subject_alternative_names = local.reverse_proxy_sans
  validation_method         = "DNS"

  tags = {
    Name = "${local.prefix}-reverse-proxy-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "reverse_proxy_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.reverse_proxy.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = local.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.value]
}

resource "aws_acm_certificate_validation" "reverse_proxy" {
  certificate_arn         = aws_acm_certificate.reverse_proxy.arn
  validation_record_fqdns = [for record in aws_route53_record.reverse_proxy_cert_validation : record.fqdn]
}
