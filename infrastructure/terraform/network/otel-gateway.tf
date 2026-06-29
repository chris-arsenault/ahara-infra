resource "aws_ssm_parameter" "observability_otlp_http_endpoint" {
  name  = "/${local.prefix}/observability/otlp-http-endpoint"
  type  = "String"
  value = "http://${module.reverse_proxy.private_ip}:${local.truenas_otlp_http_port}"
}

resource "aws_ssm_parameter" "observability_otlp_grpc_endpoint" {
  name  = "/${local.prefix}/observability/otlp-grpc-endpoint"
  type  = "String"
  value = "http://${module.reverse_proxy.private_ip}:${local.truenas_otlp_grpc_port}"
}

