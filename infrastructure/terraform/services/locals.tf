locals {
  prefix = "ahara"

  # Platform infrastructure lives under services.ahara.io so that the apex
  # zone (ahara.io) can be owned by ahara-portal without any cross-state
  # coordination. Every hostname ahara-infra manages is a subdomain of
  # local.services_domain:
  #   services.ahara.io              — parent A record (satisfies Cognito)
  #   auth.services.ahara.io         — Cognito custom domain
  #   ci.services.ahara.io           — ci-ingest
  #   dashboards.services.ahara.io   — reverse proxy (dashboards, sonar, etc.)
  #   sonar.services.ahara.io        — (handled by reverse proxy)
  services_domain = "services.${var.domain_name}"
  auth_domain     = "auth.${local.services_domain}"

  user_access_table_name = "${local.prefix}-user-access"

  # SSM parameter prefix for all shared config
  ssm_prefix = "/${local.prefix}"

  # Context objects passed to ahara-tf-patterns modules (lambda, alb-api).
  # ahara-infra constructs these directly from network module outputs —
  # no platform-context fetch is needed because this repo IS the publisher.
  lambda_ctx = {
    private_subnet_ids = var.private_subnet_ids
    lambda_sg_id       = var.ahara_lambda_sg_id
    vpn_client_sg_id   = var.vpn_client_sg_id
  }

  alb_ctx = {
    dns_name     = var.alb_dns_name
    zone_id      = var.alb_zone_id
    listener_arn = var.alb_listener_arn
  }
}
