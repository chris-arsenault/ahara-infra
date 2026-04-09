# WireGuard peer configuration stored in Secrets Manager.
# These values are static — set once, read by Terraform on every apply.
# No GitHub secrets or tfvars needed.

data "aws_secretsmanager_secret_version" "vpn_config" {
  secret_id = aws_secretsmanager_secret.vpn_config.id
}

resource "aws_secretsmanager_secret" "vpn_config" {
  name = "ahara-network-peer-config"
}

resource "aws_secretsmanager_secret_version" "vpn_config" {
  secret_id = aws_secretsmanager_secret.vpn_config.id
  secret_string = jsonencode({
    home_peer_public_key = ""
    home_lan_cidr        = "192.168.66.0/24"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

locals {
  vpn_config           = jsondecode(data.aws_secretsmanager_secret_version.vpn_config.secret_string)
  home_peer_public_key = local.vpn_config["home_peer_public_key"]
  home_lan_cidr        = local.vpn_config["home_lan_cidr"]
}
