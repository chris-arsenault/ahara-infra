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
  support_email = "support@${var.domain_name}"

  # MCP clients name the API they want with the OAuth `resource` parameter.
  resource_parameter_profile = "compatibility"

  # Registration by client metadata document waits for a provider release that sets it.

  # Production settings from Auth0's readiness checks: emails link to
  # auth.ahara.io, a new application gets no connection until its product
  # enables one, and ID tokens never authorize the Management API.
  flags {
    enable_dynamic_client_registration = true
    enable_custom_domain_in_emails     = true
    enable_client_connections          = false
    enable_idtoken_api2                = false
  }
}

# Identifier-first Universal Login is what lets a product's connection verify a
# new user's email with a code during sign-up.
resource "auth0_prompt" "ahara" {
  universal_login_experience = "new"
  identifier_first           = true
}

# --- Email: Auth0 sends through SES from no-reply@ahara.io ---
#
# Managed separately, part of the platform: the IAM user ahara-auth0-email was
# created by hand, because this stack's deployer role does not manage IAM
# users. Its one inline policy, ses-send-no-reply, allows ses:SendEmail and
# ses:SendRawEmail on the ahara.io identity only from no-reply@ahara.io. Its
# access key lives in /ahara/auth0/ses-access-key-id and
# /ahara/auth0/ses-secret-access-key; rotate it by creating a new key, updating
# both parameters, applying this stack, then deleting the old key.

data "aws_ssm_parameter" "auth0_ses_access_key_id" {
  name = "${local.ssm_prefix}/auth0/ses-access-key-id"
}

data "aws_ssm_parameter" "auth0_ses_secret_access_key" {
  name = "${local.ssm_prefix}/auth0/ses-secret-access-key"
}

resource "auth0_email_provider" "ses" {
  name                 = "ses"
  enabled              = true
  default_from_address = "no-reply@${var.domain_name}"

  credentials {
    access_key_id     = nonsensitive(data.aws_ssm_parameter.auth0_ses_access_key_id.value)
    secret_access_key = data.aws_ssm_parameter.auth0_ses_secret_access_key.value
    region            = data.aws_region.current.region
  }
}

locals {
  auth0_email_from = "Ahara <no-reply@${var.domain_name}>"

  # One layout for every code Auth0 emails; Auth0 fills {{ code }} and {{ user.email }}.
  auth0_code_emails = {
    verify_email_by_code = {
      subject = "Your Ahara verification code"
      lead    = "Enter this code to finish creating your Ahara account."
      ignore  = "If you did not sign up, you can ignore this email."
    }
    reset_email_by_code = {
      subject = "Your Ahara password reset code"
      lead    = "Enter this code to choose a new password for your Ahara account."
      ignore  = "If you did not ask to reset your password, you can ignore this email; your password is unchanged."
    }
  }
}

resource "auth0_email_template" "code" {
  for_each = local.auth0_code_emails

  template = each.key
  enabled  = true
  from     = local.auth0_email_from
  subject  = each.value.subject
  syntax   = "liquid"
  body = templatefile("${path.module}/auth0-emails/code.html", {
    title  = each.value.subject
    lead   = each.value.lead
    ignore = each.value.ignore
  })

  url_lifetime_in_seconds = 900

  depends_on = [auth0_email_provider.ses]
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
