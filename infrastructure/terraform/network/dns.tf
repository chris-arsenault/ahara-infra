resource "aws_route53_record" "wireguard" {
  zone_id = local.route53_zone_id
  name    = "wg.${local.root_domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.wireguard.dns_name
    zone_id                = aws_lb.wireguard.zone_id
    evaluate_target_health = false
  }
}

# Note: the apex A record for ahara.io lives in services/dns.tf — Cognito's
# custom domain needs to explicitly depend on it, which is only possible
# if it lives in the same module as the cognito user pool domain resource.
