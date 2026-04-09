resource "aws_eip" "this" {
  count  = var.associate_eip ? 1 : 0
  domain = "vpc"

  tags = local.eip_tags
}

resource "aws_eip_association" "this" {
  count = var.associate_eip ? 1 : 0

  allocation_id        = aws_eip.this[0].id
  network_interface_id = aws_network_interface.this.id
}
