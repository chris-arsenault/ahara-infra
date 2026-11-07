# =============================================================================
# Auth0: the shared Ahara tenant
#
# One tenant serves Ahara's products that sign people in through Auth0. This
# stack owns what is shared: the tenant settings, its Ahara branding and the
# sign-in domain auth.ahara.io. Each product's own Terraform owns its database
# connection (its own users), its applications and its APIs in the tenant.
#
# The tenant and its Terraform credential were created by hand once; the
# credential lives in /ahara/auth0/{domain,client-id,client-secret}. Product
# stacks read the same parameters to configure their own provider.
# =============================================================================

terraform {
  required_providers {
    auth0 = {
      source  = "auth0/auth0"
      version = "1.59.0"
    }
  }
}

data "aws_ssm_parameter" "auth0_domain" {
  name = "${local.ssm_prefix}/auth0/domain"
}

data "aws_ssm_parameter" "auth0_client_id" {
  name = "${local.ssm_prefix}/auth0/client-id"
}

data "aws_ssm_parameter" "auth0_client_secret" {
  name = "${local.ssm_prefix}/auth0/client-secret"
}

provider "auth0" {
  domain        = nonsensitive(data.aws_ssm_parameter.auth0_domain.value)
  client_id     = nonsensitive(data.aws_ssm_parameter.auth0_client_id.value)
  client_secret = data.aws_ssm_parameter.auth0_client_secret.value
}

locals {
  # The apex zone belongs to ahara-portal, but this one record is the
  # platform's: people sign in to every Auth0-backed product here.
  auth0_sign_in_domain = "auth.${var.domain_name}"
}

# Tenant-wide flags apply to every product in the tenant. Dynamic client
# registration lets MCP clients such as claude.ai and ChatGPT register
# themselves. Registered clients are third-party: they can use only
# domain-level connections and only APIs that grant third-party clients
# default access, so a product opts in through its own connection and API.
resource "auth0_tenant" "ahara" {
  friendly_name = "Ahara"
  picture_url   = "https://${var.domain_name}/favicon.svg"

  # MCP clients name the API they want with the OAuth `resource` parameter.
  resource_parameter_profile = "compatibility"

  # Registration by client metadata document waits for a provider release that sets it.

  flags {
    enable_dynamic_client_registration = true
  }
}

resource "auth0_branding" "ahara" {
  logo_url = "https://${var.domain_name}/favicon.svg"

  colors {
    primary         = "#818cf8"
    page_background = "#0a0a0f"
  }
}

resource "auth0_custom_domain" "ahara" {
  domain     = local.auth0_sign_in_domain
  type       = "auth0_managed_certs"
  tls_policy = "recommended"
}

resource "aws_route53_record" "auth0_sign_in" {
  zone_id = var.route53_zone_id
  name    = auth0_custom_domain.ahara.verification[0].methods[0].domain
  type    = upper(auth0_custom_domain.ahara.verification[0].methods[0].name)
  ttl     = 300
  records = [auth0_custom_domain.ahara.verification[0].methods[0].record]
}

resource "auth0_custom_domain_verification" "ahara" {
  custom_domain_id = auth0_custom_domain.ahara.id

  timeouts { create = "15m" }

  depends_on = [aws_route53_record.auth0_sign_in]
}

# Tokens requested through the custom domain carry this issuer.
resource "aws_ssm_parameter" "auth0_issuer" {
  name  = "${local.ssm_prefix}/auth0/issuer"
  type  = "String"
  value = "https://${local.auth0_sign_in_domain}/"

  depends_on = [auth0_custom_domain_verification.ahara]
}
