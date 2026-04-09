# Network-internal SSM parameters only. Cross-layer state (vpc_id, alb_*)
# that was previously published to /ahara/network/* is now exposed via the
# network module's outputs.tf and consumed directly by the services module.

resource "aws_ssm_parameter" "server_public_key" {
  name  = local.ssm_public_key_path
  type  = "String"
  value = "PENDING"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "home_peer_conf" {
  name  = "/${local.prefix}/home_peer_conf"
  type  = "String"
  value = local.home_peer_config
}
