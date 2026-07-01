# =============================================================================
# Observability ingest — Cognito M2M (client_credentials) identity
#
# Producers (the reverse-proxy Alloy gateway, EC2 log agents, and LAN producers
# such as house-sensors) obtain a client-credentials access token for the
# "observability/ingest" scope and present it as a Bearer JWT. The TrueNAS Envoy
# ingest gateway validates that token against this pool's JWKS + issuer + scope
# before forwarding to VictoriaMetrics, Loki, or the Alloy OTLP receivers.
#
# No shared secret is stored on TrueNAS — the gateway only needs Cognito's
# public JWKS/issuer. Only producers hold the client id/secret below.
# =============================================================================

resource "aws_cognito_resource_server" "observability" {
  name         = "${local.prefix}-observability"
  identifier   = "observability"
  user_pool_id = module.cognito.user_pool_id

  scope {
    scope_name        = "ingest"
    scope_description = "Write telemetry (metrics, logs, traces) to the Ahara observability backends"
  }
}

resource "aws_cognito_user_pool_client" "observability_ingest" {
  name         = "${local.prefix}-observability-ingest"
  user_pool_id = module.cognito.user_pool_id

  # Machine-to-machine client: confidential (has a secret), client_credentials
  # grant only, restricted to the observability ingest scope. No user auth
  # flows, callback, or logout URLs.
  generate_secret                      = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["${aws_cognito_resource_server.observability.identifier}/ingest"]
  supported_identity_providers         = ["COGNITO"]
}

# --- Producer credentials (consumed by ahara-infra Alloy + LAN producers) ---

resource "aws_ssm_parameter" "observability_ingest_client_id" {
  name  = "${local.ssm_prefix}/observability/ingest-client-id"
  type  = "String"
  value = aws_cognito_user_pool_client.observability_ingest.id
}

resource "aws_ssm_parameter" "observability_ingest_client_secret" {
  name  = "${local.ssm_prefix}/observability/ingest-client-secret"
  type  = "SecureString"
  value = aws_cognito_user_pool_client.observability_ingest.client_secret
}

resource "aws_ssm_parameter" "observability_ingest_scope" {
  name  = "${local.ssm_prefix}/observability/ingest-scope"
  type  = "String"
  value = "${aws_cognito_resource_server.observability.identifier}/ingest"
}

resource "aws_ssm_parameter" "observability_ingest_token_url" {
  name  = "${local.ssm_prefix}/observability/ingest-token-url"
  type  = "String"
  value = "https://${local.auth_domain}/oauth2/token"
}

# --- Public validation config (consumed by the TrueNAS Envoy ingest gateway) ---

resource "aws_ssm_parameter" "observability_ingest_issuer" {
  name  = "${local.ssm_prefix}/observability/ingest-issuer"
  type  = "String"
  value = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${module.cognito.user_pool_id}"
}

resource "aws_ssm_parameter" "observability_ingest_jwks_uri" {
  name  = "${local.ssm_prefix}/observability/ingest-jwks-uri"
  type  = "String"
  value = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${module.cognito.user_pool_id}/.well-known/jwks.json"
}
