output "private_ip" {
  value = aws_network_interface.this.private_ip
}

output "primary_network_interface_id" {
  value = aws_network_interface.this.id
}

output "public_ip" {
  value = var.associate_eip ? aws_eip.this[0].public_ip : ""
}

output "network_interface_id" {
  value = aws_network_interface.this.id
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.this.name
}

output "launch_template_id" {
  value = aws_launch_template.this.id
}
