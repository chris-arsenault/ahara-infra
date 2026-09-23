# =============================================================================
# Score Shelf publisher — Cognito M2M (client_credentials) identity
#
# The composition agent on the dev box obtains a client-credentials access
# token for the "score-shelf/publish" scope and presents it to
# api.score-shelf.ahara.io to publish new score versions. The score-shelf API
# authorizes the call by this client's id and scope; the shared ALB only
# verifies the token's signature and issuer.
#
# Lives here rather than in the score-shelf repo because project deployers
# cannot create resource servers (cognito-pool is ahara-infra only). Pattern:
# observability-ingest.tf.
# =============================================================================

resource "aws_cognito_resource_server" "score_shelf" {
  name         = "${local.prefix}-score-shelf"
  identifier   = "score-shelf"
  user_pool_id = module.cognito.user_pool_id

  scope {
    scope_name        = "publish"
    scope_description = "Publish score versions to Score Shelf"
  }
}

resource "aws_cognito_user_pool_client" "score_shelf_publisher" {
  name         = "${local.prefix}-score-shelf-publisher"
  user_pool_id = module.cognito.user_pool_id

  # Machine-to-machine client: confidential, client_credentials grant only,
  # restricted to the score-shelf publish scope.
  generate_secret                      = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["${aws_cognito_resource_server.score_shelf.identifier}/publish"]
  supported_identity_providers         = ["COGNITO"]
}

# --- Publisher credentials (consumed by the dev-box publish script) ---

resource "aws_ssm_parameter" "score_shelf_publisher_client_id" {
  name  = "${local.ssm_prefix}/score-shelf/publisher-client-id"
  type  = "String"
  value = aws_cognito_user_pool_client.score_shelf_publisher.id
}

resource "aws_ssm_parameter" "score_shelf_publisher_client_secret" {
  name  = "${local.ssm_prefix}/score-shelf/publisher-client-secret"
  type  = "SecureString"
  value = aws_cognito_user_pool_client.score_shelf_publisher.client_secret
}

resource "aws_ssm_parameter" "score_shelf_publisher_scope" {
  name  = "${local.ssm_prefix}/score-shelf/publisher-scope"
  type  = "String"
  value = "${aws_cognito_resource_server.score_shelf.identifier}/publish"
}

resource "aws_ssm_parameter" "score_shelf_publisher_token_url" {
  name  = "${local.ssm_prefix}/score-shelf/publisher-token-url"
  type  = "String"
  value = "https://${local.auth_domain}/oauth2/token"
}
