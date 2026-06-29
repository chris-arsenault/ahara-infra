resource "aws_iam_role" "nat" {
  name_prefix        = "${local.prefix}-nat-"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_instance_profile" "nat" {
  name_prefix = "${local.prefix}-nat-"
  role        = aws_iam_role.nat.name
}

resource "aws_iam_role_policy_attachment" "nat_ssm" {
  role       = aws_iam_role.nat.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

module "nat" {
  source = "./modules/ec2_instance"

  name                 = "${local.prefix}-nat"
  iam_instance_profile = aws_iam_instance_profile.nat.name
  subnet_id            = aws_subnet.public.id
  security_group_ids   = [aws_security_group.nat.id]
  associate_eip        = true
  instance_type        = "t3.nano"

  user_data = templatefile("${path.module}/templates/common_user_data.sh.tpl", {
    EXTRA_SNIPPET = templatefile("${path.module}/templates/nat_instance_user_data.sh.tpl", {
      PRIVATE_SUBNET_CIDR = local.private_subnet_cidr
    })
    HARDENING_SCRIPT = local.hardening_script
    ALLOY_CONFIG = templatefile("${path.module}/templates/alloy_config.alloy.tpl", {
      host_role                    = "nat"
      loki_push_url                = "http://${module.reverse_proxy.private_ip}:${local.truenas_loki_port}/loki/api/v1/push"
      loki_gateway_enabled         = false
      loki_gateway_port            = local.truenas_loki_port
      truenas_observability_host   = local.truenas_observability_host
      truenas_loki_port            = local.truenas_loki_port
      truenas_otlp_grpc_port       = local.truenas_otlp_grpc_port
      truenas_otlp_http_port       = local.truenas_otlp_http_port
      truenas_victoriametrics_port = local.truenas_victoriametrics_port
      otlp_gateway_enabled         = false
      file_logs                    = []
      journal_logs = [
        {
          match_expr = "SYSLOG_IDENTIFIER=kernel"
          source     = "kernel"
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
