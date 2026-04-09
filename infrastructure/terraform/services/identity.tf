# =============================================================================
# Cognito User Pool (shared across all ahara apps)
#
# Auth domain: auth.services.ahara.io (not auth.ahara.io).
# Putting Cognito on a subdomain of services.ahara.io means its parent-
# domain DNS requirement is satisfied by services/dns.tf without touching
# the apex zone (ahara.io), which is owned by ahara-portal.
# =============================================================================

module "cognito" {
  source = "./modules/cognito"

  user_pool_name   = coalesce(var.cognito_user_pool_name, "${local.prefix}-users")
  domain_name      = local.auth_domain
  domain_zone_name = var.domain_name
  clients = length(var.cognito_clients) > 0 ? var.cognito_clients : {
    svap    = "svap-app"
    canonry = "${local.prefix}-canonry-app"
  }
  pre_auth_lambda_arn = module.auth_trigger.function_arn

  # Cognito CreateUserPoolDomain verifies that the PARENT domain
  # (services.ahara.io) has an A record before it succeeds. That record
  # lives in services/dns.tf — this dep ensures it is created first.
  depends_on = [aws_route53_record.services_parent]
}

# =============================================================================
# User Access Table (gates per-app access via pre-auth Lambda)
# =============================================================================

resource "aws_dynamodb_table" "user_access" {
  name         = local.user_access_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "username"

  attribute {
    name = "username"
    type = "S"
  }
}


# =============================================================================
# ALB Cognito Client (for authenticate-cognito action on dashboard routes)
# =============================================================================

resource "aws_cognito_user_pool_client" "alb" {
  name         = "${local.prefix}-alb"
  user_pool_id = module.cognito.user_pool_id

  generate_secret                      = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers         = ["COGNITO"]

  callback_urls = [
    "https://dashboards.${local.services_domain}/oauth2/idpresponse"
  ]

  logout_urls = [
    "https://dashboards.${local.services_domain}/logout"
  ]
}
