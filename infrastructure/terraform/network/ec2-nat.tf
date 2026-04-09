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
    HARDENING_SCRIPT        = local.hardening_script
    VECTOR_SERVICE_UNIT     = local.vector_service_unit
    VECTOR_SERVICE_OVERRIDE = local.vector_service_override
    VECTOR_CONFIG = templatefile("${path.module}/templates/vector_config.toml.tpl", {
      file_logs = []
      journal_logs = [
        {
          match_field     = "SYSLOG_IDENTIFIER"
          match_value     = "kernel"
          log_group_name  = aws_cloudwatch_log_group.nat.name
          log_stream_name = "{instance_id}/kernel"
        },
        {
          match_field     = "SYSLOG_IDENTIFIER"
          match_value     = "sshd"
          log_group_name  = aws_cloudwatch_log_group.nat.name
          log_stream_name = "{instance_id}/journal-sshd"
        },
        {
          match_field     = "SYSLOG_IDENTIFIER"
          match_value     = "auditd"
          log_group_name  = aws_cloudwatch_log_group.nat.name
          log_stream_name = "{instance_id}/journal-audit"
        }
      ]
    })
  })
}
