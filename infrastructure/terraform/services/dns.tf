# =============================================================================
# DNS records owned by services
# =============================================================================

# A record for services.ahara.io — the parent of auth.services.ahara.io.
# Required by Cognito's custom domain feature: Cognito verifies that the
# parent of the custom domain has an A record before CreateUserPoolDomain
# succeeds. Aliases the shared ALB.
#
# The apex (ahara.io) is deliberately NOT claimed here — it's reserved for
# ahara-portal to manage independently.
resource "aws_route53_record" "services_parent" {
  zone_id = var.route53_zone_id
  name    = local.services_domain
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = false
  }
}

# Publish zone id so consumer projects can read it without a name-based zone lookup.
resource "aws_ssm_parameter" "dns_ahara_zone_id" {
  name  = "${local.ssm_prefix}/dns/ahara-io-zone-id"
  type  = "String"
  value = var.route53_zone_id
}
