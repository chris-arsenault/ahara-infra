# =============================================================================
# Grafana Dashboard Bootstrap Lambda
#
# Invoked by the ahara-observability CI workflow after the Grafana stack deploys.
# It reaches Grafana over the private LAN, creates/updates the service account
# used for dashboard deploys, rotates that token, and stores it in SSM.
# =============================================================================

locals {
  grafana_dashboard_bootstrap_function_parameter = "${local.ssm_prefix}/observability/grafana-dashboard-deployer/bootstrap-function-name"
}

data "archive_file" "grafana_dashboard_bootstrap" {
  type        = "zip"
  source_file = "${path.module}/../../../backend/target/lambda/grafana-dashboard-bootstrap/bootstrap"
  output_path = "${path.module}/grafana-dashboard-bootstrap-lambda.zip"
}

resource "aws_cloudwatch_log_group" "grafana_dashboard_bootstrap" {
  name              = "/aws/lambda/${local.prefix}-grafana-dashboard-bootstrap"
  retention_in_days = 14
}

resource "aws_iam_role" "grafana_dashboard_bootstrap" {
  name               = "${local.prefix}-grafana-dashboard-bootstrap"
  assume_role_policy = data.aws_iam_policy_document.auth_trigger_assume.json
}

resource "aws_iam_role_policy_attachment" "grafana_dashboard_bootstrap_basic" {
  role       = aws_iam_role.grafana_dashboard_bootstrap.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "grafana_dashboard_bootstrap_vpc" {
  role       = aws_iam_role.grafana_dashboard_bootstrap.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "grafana_dashboard_bootstrap_ssm" {
  name = "${local.prefix}-grafana-dashboard-bootstrap-ssm"
  role = aws_iam_role.grafana_dashboard_bootstrap.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}/observability/grafana-admin-password"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.grafana_dashboard_deploy_token_parameter}"
      }
    ]
  })
}

resource "aws_lambda_function" "grafana_dashboard_bootstrap" {
  function_name = "${local.prefix}-grafana-dashboard-bootstrap"
  role          = aws_iam_role.grafana_dashboard_bootstrap.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"

  filename         = data.archive_file.grafana_dashboard_bootstrap.output_path
  source_code_hash = data.archive_file.grafana_dashboard_bootstrap.output_base64sha256

  timeout     = 660
  memory_size = 128

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.ahara_lambda_sg_id]
  }

  environment {
    variables = {
      GRAFANA_ADMIN_PASSWORD_PARAMETER = "${local.ssm_prefix}/observability/grafana-admin-password"
      GRAFANA_ADMIN_USER               = "admin"
      GRAFANA_SERVICE_ACCOUNT_NAME     = "ahara-dashboard-deployer"
      GRAFANA_SERVICE_ACCOUNT_ROLE     = "Editor"
      GRAFANA_TOKEN_NAME               = "ci-dashboard-deployer"
      GRAFANA_TOKEN_PARAMETER          = local.grafana_dashboard_deploy_token_parameter
      GRAFANA_URL                      = "http://192.168.66.3:30038"
    }
  }

  depends_on = [aws_cloudwatch_log_group.grafana_dashboard_bootstrap]
}

resource "aws_ssm_parameter" "grafana_dashboard_bootstrap_function" {
  name  = local.grafana_dashboard_bootstrap_function_parameter
  type  = "String"
  value = aws_lambda_function.grafana_dashboard_bootstrap.function_name
}
