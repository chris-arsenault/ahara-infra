resource "aws_route53_record" "reverse_proxy_alias_a" {
  for_each = toset(local.reverse_proxy_hostnames)

  zone_id = local.route53_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_lb.reverse_proxy.dns_name
    zone_id                = aws_lb.reverse_proxy.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "reverse_proxy_alias_aaaa" {
  for_each = toset(local.reverse_proxy_hostnames)

  zone_id = local.route53_zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_lb.reverse_proxy.dns_name
    zone_id                = aws_lb.reverse_proxy.zone_id
    evaluate_target_health = true
  }
}
