# Shared control metadata only. Clients own their workflows and registrations.
resource "aws_dynamodb_table" "pipeline_registry" {
  name         = "${local.prefix}-pipeline-registry"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "workflow_arn"
  attribute {
    name = "workflow_arn"
    type = "S"
  }
}
resource "aws_dynamodb_table" "pipeline_jobs" {
  name         = "${local.prefix}-pipeline-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "execution_arn"
  attribute {
    name = "execution_arn"
    type = "S"
  }
}
resource "aws_ssm_parameter" "pipeline_registry" {
  name  = "${local.ssm_prefix}/pipelines/registry-table"
  type  = "String"
  value = aws_dynamodb_table.pipeline_registry.name
}
resource "aws_ssm_parameter" "pipeline_jobs" {
  name  = "${local.ssm_prefix}/pipelines/jobs-table"
  type  = "String"
  value = aws_dynamodb_table.pipeline_jobs.name
}
resource "aws_iam_role" "pipeline_status" {
  name               = "${local.prefix}-pipeline-status"
  assume_role_policy = data.aws_iam_policy_document.auth_trigger_assume.json
}
resource "aws_iam_role_policy_attachment" "pipeline_status_basic" {
  role       = aws_iam_role.pipeline_status.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy_attachment" "pipeline_status_vpc" {
  role       = aws_iam_role.pipeline_status.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
resource "aws_iam_role_policy" "pipeline_status" {
  role = aws_iam_role.pipeline_status.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = aws_dynamodb_table.pipeline_registry.arn },
      { Effect = "Allow", Action = ["dynamodb:PutItem"], Resource = aws_dynamodb_table.pipeline_jobs.arn },
    ]
  })
}
module "pipeline_status" {
  source   = "git::https://github.com/chris-arsenault/ahara-tf-patterns.git//modules/lambda?ref=7922d0245fca2c31db057e11abab26b074986b5f"
  name     = "${local.prefix}-pipeline-status"
  binary   = "${path.module}/../../../backend/target/lambda/pipeline-status/bootstrap"
  role_arn = aws_iam_role.pipeline_status.arn
  vpc      = local.lambda_ctx
  timeout  = 30
  environment = {
    REGISTRY_TABLE              = aws_dynamodb_table.pipeline_registry.name
    JOBS_TABLE                  = aws_dynamodb_table.pipeline_jobs.name
    OTEL_EXPORTER_OTLP_ENDPOINT = var.otlp_http_endpoint
    DEPLOYMENT_ENVIRONMENT      = "production"
  }
}
resource "aws_cloudwatch_event_rule" "pipeline_status" {
  name = "${local.prefix}-pipeline-status"
  lifecycle {
    precondition {
      condition     = var.control_plane_revision != ""
      error_message = "The pipeline status rule requires the active deployer permissions."
    }
  }
  event_pattern = jsonencode({
    source        = ["aws.states"]
    "detail-type" = ["Step Functions Execution Status Change"]
  })
}
resource "aws_cloudwatch_event_target" "pipeline_status" {
  rule = aws_cloudwatch_event_rule.pipeline_status.name
  arn  = module.pipeline_status.function_arn
}
resource "aws_lambda_permission" "pipeline_status_events" {
  statement_id  = "AllowExecutionStatusEvents"
  action        = "lambda:InvokeFunction"
  function_name = module.pipeline_status.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.pipeline_status.arn
}
