resource "aws_cloudwatch_log_group" "reverse_proxy" {
  name              = "/aws/${local.prefix}/reverse-proxy"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "wireguard" {
  name              = "/aws/${local.prefix}/wireguard"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "nat" {
  name              = "/aws/${local.prefix}/nat"
  retention_in_days = 30
}

resource "aws_flow_log" "vpc" {
  log_destination      = "${var.security_log_bucket_arn}/vpc-flow-logs"
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.this.id

  destination_options {
    file_format                = "parquet"
    hive_compatible_partitions = true
    per_hour_partition         = true
  }

  tags = {
    Name = "${local.prefix}-vpc-flow-logs"
  }

  depends_on = [terraform_data.security_log_bucket_policy]
}

resource "aws_route53_resolver_query_log_config" "vpc" {
  name            = "${local.prefix}-resolver-query-logs"
  destination_arn = var.security_log_bucket_arn

  tags = {
    Name = "${local.prefix}-resolver-query-logs"
  }

  depends_on = [terraform_data.security_log_bucket_policy]
}

resource "aws_route53_resolver_query_log_config_association" "vpc" {
  resolver_query_log_config_id = aws_route53_resolver_query_log_config.vpc.id
  resource_id                  = aws_vpc.this.id
}
