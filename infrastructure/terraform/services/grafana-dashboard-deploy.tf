# =============================================================================
# Grafana Dashboard Deploy Lambda
#
# Direct-invoked by the shared CI workflow. Product repos send dashboard JSON;
# this Lambda reads the Grafana service-account token from SSM and upserts the
# dashboards into the shared Ahara Grafana instance.
# =============================================================================

locals {
  grafana_dashboard_deploy_token_parameter = "${local.ssm_prefix}/observability/grafana-dashboard-deployer-token"
}

data "archive_file" "grafana_dashboard_deploy" {
  type        = "zip"
  source_file = "${path.module}/../../../backend/target/lambda/grafana-dashboard-deploy/bootstrap"
  output_path = "${path.module}/grafana-dashboard-deploy-lambda.zip"
}

resource "aws_cloudwatch_log_group" "grafana_dashboard_deploy" {
  name              = "/aws/lambda/${local.prefix}-grafana-dashboard-deploy"
  retention_in_days = 14
}

resource "aws_iam_role" "grafana_dashboard_deploy" {
  name               = "${local.prefix}-grafana-dashboard-deploy"
  assume_role_policy = data.aws_iam_policy_document.auth_trigger_assume.json
}

resource "aws_iam_role_policy_attachment" "grafana_dashboard_deploy_basic" {
  role       = aws_iam_role.grafana_dashboard_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "grafana_dashboard_deploy_ssm" {
  name = "${local.prefix}-grafana-dashboard-deploy-ssm"
  role = aws_iam_role.grafana_dashboard_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.grafana_dashboard_deploy_token_parameter}"
      }
    ]
  })
}

resource "aws_lambda_function" "grafana_dashboard_deploy" {
  function_name = "${local.prefix}-grafana-dashboard-deploy"
  role          = aws_iam_role.grafana_dashboard_deploy.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"

  filename         = data.archive_file.grafana_dashboard_deploy.output_path
  source_code_hash = data.archive_file.grafana_dashboard_deploy.output_base64sha256

  timeout                        = 30
  memory_size                    = 128
  reserved_concurrent_executions = 2

  environment {
    variables = {
      GRAFANA_ALLOWED_DATASOURCE_UIDS = "victoriametrics,loki,tempo,influxdb-sensors,fewxrdtvmrk00a,aezaej38ebf9ce"
      GRAFANA_MANAGED_TAG_PREFIX      = "ahara:repo:"
      GRAFANA_NAMESPACE               = "default"
      GRAFANA_TOKEN_PARAMETER         = local.grafana_dashboard_deploy_token_parameter
      GRAFANA_URL                     = "https://dashboards.services.ahara.io"
    }
  }

  depends_on = [aws_cloudwatch_log_group.grafana_dashboard_deploy]
}

resource "aws_ssm_parameter" "grafana_dashboard_deploy_function" {
  name  = "${local.ssm_prefix}/observability/grafana-dashboard-deployer/function-name"
  type  = "String"
  value = aws_lambda_function.grafana_dashboard_deploy.function_name
}

resource "aws_ssm_parameter" "grafana_dashboard_deploy_token_parameter" {
  name  = "${local.ssm_prefix}/observability/grafana-dashboard-deployer/token-parameter"
  type  = "String"
  value = local.grafana_dashboard_deploy_token_parameter
}
