# =============================================================================
# Legacy CI history migration — shared RDS ci_builds to TrueNAS engineering DB
#
# This is a rollout bridge, not a permanent ingestion path. The pre-cutover
# invocation copies a consistent source snapshot before ci-ingest changes its
# connection. The post-cutover invocation catches any reports written between
# that snapshot and the Lambda update. Both invocations are idempotent and fail
# if every source run_id cannot be verified in the destination.
# =============================================================================

data "archive_file" "ci_history_migrate" {
  type        = "zip"
  source_file = "${path.module}/../../../backend/target/lambda/ci-history-migrate/bootstrap"
  output_path = "${path.module}/ci-history-migrate-lambda.zip"
}

resource "aws_cloudwatch_log_group" "ci_history_migrate" {
  name              = "/aws/lambda/${local.prefix}-ci-history-migrate"
  retention_in_days = 14
}

resource "aws_iam_role" "ci_history_migrate" {
  name               = "${local.prefix}-ci-history-migrate"
  assume_role_policy = data.aws_iam_policy_document.auth_trigger_assume.json
}

resource "aws_iam_role_policy_attachment" "ci_history_migrate_basic" {
  role       = aws_iam_role.ci_history_migrate.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "ci_history_migrate_vpc" {
  role       = aws_iam_role.ci_history_migrate.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "ci_history_migrate_ssm" {
  name = "${local.prefix}-ci-history-migrate-ssm"
  role = aws_iam_role.ci_history_migrate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:GetParameter"]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/ahara/db/ahara/*",
          "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/ahara/truenas-db/ahara-observability/engineering/*",
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "ci_history_migrate" {
  function_name = "${local.prefix}-ci-history-migrate"
  role          = aws_iam_role.ci_history_migrate.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"

  filename         = data.archive_file.ci_history_migrate.output_path
  source_code_hash = data.archive_file.ci_history_migrate.output_base64sha256

  timeout     = 120
  memory_size = 256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.ahara_lambda_sg_id]
  }

  environment {
    variables = {
      SOURCE_DB_HOST            = aws_db_instance.ahara.address
      SOURCE_DB_PORT            = tostring(aws_db_instance.ahara.port)
      SOURCE_DB_NAME            = aws_db_instance.ahara.db_name
      SOURCE_DB_SSM_PREFIX      = "/ahara/db/ahara"
      DESTINATION_DB_HOST       = "192.168.66.3"
      DESTINATION_DB_PORT       = "5432"
      DESTINATION_DB_NAME       = var.truenas_db_stacks["ahara-observability"].databases["engineering"].db_name
      DESTINATION_DB_SSM_PREFIX = "/ahara/truenas-db/ahara-observability/engineering"
      RUST_LOG                  = "info"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.ci_history_migrate,
    aws_iam_role_policy.ci_history_migrate_ssm,
    aws_iam_role_policy_attachment.ci_history_migrate_basic,
    aws_iam_role_policy_attachment.ci_history_migrate_vpc,
  ]
}

resource "aws_lambda_invocation" "ci_history_pre_cutover" {
  function_name = aws_lambda_function.ci_history_migrate.function_name
  input         = jsonencode({ phase = "pre_cutover" })

  triggers = {
    function_code      = aws_lambda_function.ci_history_migrate.source_code_hash
    destination_schema = filesha256("${path.module}/../../../backend/ci-ingest/migrations/001_engineering_quality.sql")
  }

  depends_on = [aws_lambda_invocation.engineering_quality_database]
}

resource "aws_lambda_invocation" "ci_history_post_cutover" {
  function_name = aws_lambda_function.ci_history_migrate.function_name
  input         = jsonencode({ phase = "post_cutover" })

  triggers = {
    function_code      = aws_lambda_function.ci_history_migrate.source_code_hash
    destination_schema = filesha256("${path.module}/../../../backend/ci-ingest/migrations/001_engineering_quality.sql")
  }

  depends_on = [module.ci_ingest]
}
