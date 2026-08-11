# =============================================================================
# CI Ingest Lambda — receives engineering reports, stores in TrueNAS PostgreSQL
# Attached to ci.services.ahara.io on the shared ALB with an unauthenticated route.
# =============================================================================

resource "random_password" "ci_ingest_token" {
  length  = 32
  special = false
}

module "ci_ingest" {
  source   = "git::https://github.com/chris-arsenault/ahara-tf-patterns.git//modules/alb-api"
  prefix   = "${local.prefix}-ci-ingest"
  hostname = "ci.${local.services_domain}"

  vpc = local.lambda_ctx
  alb = local.alb_ctx

  environment = {
    DB_HOST       = "192.168.66.3"
    DB_PORT       = "5432"
    DB_NAME       = var.truenas_db_stacks["ahara-observability"].databases["engineering"].db_name
    DB_SSM_PREFIX = "/ahara/truenas-db/ahara-observability/engineering"
    INGEST_TOKEN  = random_password.ci_ingest_token.result
    MIGRATION_GATE = sha256(
      aws_lambda_invocation.ci_history_pre_cutover.result
    )
  }

  iam_policy = [jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = ["arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/ahara/truenas-db/ahara-observability/engineering/*"]
      }
    ]
  })]

  lambdas = {
    ingest = {
      binary = "${path.module}/../../../backend/target/lambda/ci-ingest/bootstrap"
      routes = [{ priority = 150, paths = ["/*"], authenticated = false }]
    }
  }

}

# --- SSM outputs ---

resource "aws_ssm_parameter" "ci_ingest_url" {
  name  = "${local.ssm_prefix}/ci/url"
  type  = "String"
  value = "https://ci.${local.services_domain}"
}

resource "aws_ssm_parameter" "ci_ingest_token" {
  name  = "${local.ssm_prefix}/ci/ingest-token"
  type  = "SecureString"
  value = random_password.ci_ingest_token.result
}
