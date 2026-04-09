resource "aws_network_interface" "this" {
  subnet_id         = var.subnet_id
  security_groups   = var.security_group_ids
  source_dest_check = false

  tags = local.eni_tags
}
