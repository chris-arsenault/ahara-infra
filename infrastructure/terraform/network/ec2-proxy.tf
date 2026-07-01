resource "aws_iam_role" "reverse_proxy" {
  name_prefix        = "${local.prefix}-proxy-"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_instance_profile" "reverse_proxy" {
  name_prefix = "${local.prefix}-proxy-"
  role        = aws_iam_role.reverse_proxy.name
}

resource "aws_iam_role_policy_attachment" "reverse_proxy_ssm" {
  role       = aws_iam_role.reverse_proxy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

module "reverse_proxy" {
  source = "./modules/ec2_instance"

  name                 = "${local.prefix}-reverse-proxy"
  iam_instance_profile = aws_iam_instance_profile.reverse_proxy.name
  subnet_id            = aws_subnet.private.id
  security_group_ids = concat(
    [aws_security_group.reverse_proxy.id],
    [for sg in aws_security_group.reverse_proxy_service : sg.id]
  )
  refresh_schedule_state = "DISABLED"

  user_data = templatefile("${path.module}/templates/common_user_data.sh.tpl", {
    EXTRA_SNIPPET = join("\n", [
      templatefile("${path.module}/templates/reverse_proxy_user_data.sh.tpl", {
        ROUTES = local.reverse_proxy_routes
      }),
    ])
    HARDENING_SCRIPT        = local.hardening_script
    VECTOR_SERVICE_UNIT     = local.vector_service_unit
    VECTOR_SERVICE_OVERRIDE = local.vector_service_override
    VECTOR_CONFIG = templatefile("${path.module}/templates/vector_config.toml.tpl", {
      file_logs = [
        {
          file_path       = "/var/log/cloud-init-output.log"
          log_group_name  = aws_cloudwatch_log_group.reverse_proxy.name
          log_stream_name = "{instance_id}/cloud-init-output"
        },
        {
          file_path       = "/var/log/nginx/*_access.log"
          log_group_name  = aws_cloudwatch_log_group.reverse_proxy.name
          log_stream_name = "{instance_id}/nginx-access"
        },
        {
          file_path       = "/var/log/nginx/*_error.log"
          log_group_name  = aws_cloudwatch_log_group.reverse_proxy.name
          log_stream_name = "{instance_id}/nginx-error"
        }
      ]
      journal_logs = [
        {
          match_field     = "SYSLOG_IDENTIFIER"
          match_value     = "nginx"
          log_group_name  = aws_cloudwatch_log_group.reverse_proxy.name
          log_stream_name = "{instance_id}/journal-nginx"
        },
        {
          match_field     = "SYSLOG_IDENTIFIER"
          match_value     = "sshd"
          log_group_name  = aws_cloudwatch_log_group.reverse_proxy.name
          log_stream_name = "{instance_id}/journal-sshd"
        },
        {
          match_field     = "SYSLOG_IDENTIFIER"
          match_value     = "auditd"
          log_group_name  = aws_cloudwatch_log_group.reverse_proxy.name
          log_stream_name = "{instance_id}/journal-audit"
        }
      ]
    })
    ALLOY_CONFIG = templatefile("${path.module}/templates/alloy_config.alloy.tpl", {
      host_role                    = "reverse-proxy"
      loki_push_url                = "http://${local.truenas_observability_host}:${local.truenas_loki_port}/loki/api/v1/push"
      loki_gateway_enabled         = true
      loki_gateway_port            = local.truenas_loki_port
      truenas_observability_host   = local.truenas_observability_host
      truenas_loki_port            = local.truenas_loki_port
      truenas_otlp_grpc_port       = local.truenas_otlp_grpc_port
      truenas_otlp_http_port       = local.truenas_otlp_http_port
      truenas_victoriametrics_port = local.truenas_victoriametrics_port
      otlp_gateway_enabled         = true
      wg_textfile_dir              = ""
      file_logs = [
        {
          file_path = "/var/log/cloud-init-output.log"
          source    = "cloud-init-output"
        },
        {
          file_path = "/var/log/nginx/*_access.log"
          source    = "nginx-access"
        },
        {
          file_path = "/var/log/nginx/*_error.log"
          source    = "nginx-error"
        }
      ]
      journal_logs = [
        {
          match_expr = "SYSLOG_IDENTIFIER=nginx"
          source     = "journal-nginx"
        },
        {
          match_expr = "SYSLOG_IDENTIFIER=sshd"
          source     = "journal-sshd"
        },
        {
          match_expr = "SYSLOG_IDENTIFIER=auditd"
          source     = "journal-audit"
        }
      ]
    })
  })
}
