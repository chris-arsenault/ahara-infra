output "vpc_id" {
  value = aws_vpc.this.id
}

output "private_subnet_ids" {
  value = [aws_subnet.private.id, aws_subnet.private_b.id]
}

output "public_subnet_ids" {
  value = [aws_subnet.public.id, aws_subnet.public_b.id]
}

output "alb_arn" {
  value = aws_lb.reverse_proxy.arn
}

output "alb_dns_name" {
  value = aws_lb.reverse_proxy.dns_name
}

output "alb_zone_id" {
  value = aws_lb.reverse_proxy.zone_id
}

output "alb_listener_arn" {
  value = aws_lb_listener.https.arn
}

output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "ahara_lambda_sg_id" {
  value = aws_security_group.ahara_lambda.id
}

output "vpn_client_sg_id" {
  value = aws_security_group.vpn_client.id
}

output "route53_zone_id" {
  value = local.route53_zone_id
}

output "reverse_proxy_target_group_arn" {
  value = aws_lb_target_group.reverse_proxy.arn
}

output "reverse_proxy_cognito_hosts" {
  value = local.reverse_proxy_cognito_hosts
}
