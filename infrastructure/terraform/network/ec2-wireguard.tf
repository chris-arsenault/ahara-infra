resource "aws_iam_role" "wireguard" {
  name_prefix        = "${local.prefix}-"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_instance_profile" "wireguard" {
  name_prefix = "${local.prefix}-"
  role        = aws_iam_role.wireguard.name
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.wireguard.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "wireguard_limited_perms" {
  statement {
    sid = "ManageNamespacedSsmParameters"
    actions = [
      "ssm:PutParameter",
      "ssm:DeleteParameter",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource"
    ]
    resources = ["arn:aws:ssm:*:*:parameter/${local.prefix}/*"]
  }

  statement {
    sid = "RWWireGuardKeys"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:PutSecretValue"
    ]
    resources = [aws_secretsmanager_secret.wg_keys.arn]
  }
}

resource "aws_iam_role_policy" "inline_modules" {
  role   = aws_iam_role.wireguard.id
  name   = "${local.prefix}-ssm-policy"
  policy = data.aws_iam_policy_document.wireguard_limited_perms.json
}


module "wireguard" {
  source = "./modules/ec2_instance"

  name                 = "${local.prefix}-wireguard-server"
  iam_instance_profile = aws_iam_instance_profile.wireguard.name
  subnet_id            = aws_subnet.private.id
  security_group_ids   = [aws_security_group.wireguard.id]

  user_data = templatefile("${path.module}/templates/common_user_data.sh.tpl", {
    EXTRA_SNIPPET = templatefile("${path.module}/templates/wireguard_user_data.sh.tpl", {
      WG_PORT             = local.wireguard_port
      WG_CIDR             = local.wireguard_cidr
      WG_CIDR_HOST        = local.wireguard_cidr_host
      HOME_LAN_CIDR       = local.home_lan_cidr
      HOME_PEER_PUBKEY    = local.home_peer_public_key
      LAPTOP_PEER_PUBKEY  = local.laptop_peer_public_key
      PRIVATE_SUBNET_CIDR = local.private_subnet_cidr
      SSM_PUBLIC_KEY_PATH = local.ssm_public_key_path
      AWS_REGION          = "us-east-1"
      SECRET_ID           = aws_secretsmanager_secret.wg_keys.id
      WG_SERVER_IP        = cidrhost(local.wireguard_cidr, 1)
      VPC_DNS             = cidrhost(local.vpc_cidr, 2)
    })
    HARDENING_SCRIPT        = local.hardening_script
    VECTOR_SERVICE_UNIT     = local.vector_service_unit
    VECTOR_SERVICE_OVERRIDE = local.vector_service_override
    VECTOR_CONFIG = templatefile("${path.module}/templates/vector_config.toml.tpl", {
      file_logs = []
      journal_logs = [
        {
          match_field     = "SYSTEMD_UNIT"
          match_value     = "wg-quick@wg0.service"
          log_group_name  = aws_cloudwatch_log_group.wireguard.name
          log_stream_name = "{instance_id}/wg-quick"
        },
        {
          match_field     = "SYSTEMD_UNIT"
          match_value     = "wg-healthcheck.service"
          log_group_name  = aws_cloudwatch_log_group.wireguard.name
          log_stream_name = "{instance_id}/wg-healthcheck"
        },
        {
          match_field     = "SYSLOG_IDENTIFIER"
          match_value     = "kernel"
          log_group_name  = aws_cloudwatch_log_group.wireguard.name
          log_stream_name = "{instance_id}/kernel"
        },
        {
          match_field     = "SYSLOG_IDENTIFIER"
          match_value     = "sshd"
          log_group_name  = aws_cloudwatch_log_group.wireguard.name
          log_stream_name = "{instance_id}/journal-sshd"
        },
        {
          match_field     = "SYSLOG_IDENTIFIER"
          match_value     = "auditd"
          log_group_name  = aws_cloudwatch_log_group.wireguard.name
          log_stream_name = "{instance_id}/journal-audit"
        }
      ]
    })
  })
}
