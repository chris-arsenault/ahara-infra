# =============================================================================
# Ops Dashboard Lambda — CloudWatch Logs Insights over Ahara OTEL-style logs
# =============================================================================

locals {
  ops_dashboard_hostname = "ops.${local.services_domain}"
  ops_dashboard_cognito = {
    issuer = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${module.cognito.user_pool_id}"
    jwks   = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${module.cognito.user_pool_id}/.well-known/jwks.json"
  }
}

module "ops_dashboard" {
  source   = "git::https://github.com/chris-arsenault/ahara-tf-patterns.git//modules/alb-api"
  prefix   = "${local.prefix}-ops-dashboard"
  hostname = local.ops_dashboard_hostname

  vpc     = local.lambda_ctx
  alb     = local.alb_ctx
  cognito = local.ops_dashboard_cognito

  environment = {
    CORS_ALLOWED_ORIGIN = "https://mail.${var.domain_name}"
    LOG_GROUP_PREFIXES  = "/aws/lambda/"
    MAX_LOG_GROUPS      = "50"
  }

  iam_policy = [jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetQueryResults",
          "logs:StopQuery"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["logs:StartQuery"]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*",
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*:*"
        ]
      }
    ]
  })]

  lambdas = {
    api = {
      binary = "${path.module}/../../../backend/target/lambda/ops-dashboard/bootstrap"
      routes = [
        {
          priority      = 160
          paths         = ["/*"]
          methods       = ["OPTIONS"]
          authenticated = false
        },
        {
          priority      = 161
          paths         = ["/health", "/api/ops/health"]
          methods       = ["GET", "HEAD"]
          authenticated = false
        },
        {
          priority      = 162
          paths         = ["/*"]
          authenticated = true
        }
      ]
      reserved_concurrent_executions = 2
    }
  }
}

resource "aws_ssm_parameter" "ops_dashboard_url" {
  name  = "${local.ssm_prefix}/ops-dashboard/url"
  type  = "String"
  value = "https://${local.ops_dashboard_hostname}"
}
