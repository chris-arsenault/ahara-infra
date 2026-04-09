resource "aws_lb" "wireguard" {
  name                             = "${local.prefix}-wg-nlb"
  load_balancer_type               = "network"
  internal                         = false
  enable_cross_zone_load_balancing = true
  subnets = [
    aws_subnet.public.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name = "${local.prefix}-wg-nlb"
  }
}

resource "aws_lb_target_group" "wireguard" {
  name        = "${local.prefix}-wg-tg"
  port        = local.wireguard_port
  protocol    = "UDP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    enabled  = true
    port     = "31000"
    protocol = "TCP"
  }

  tags = {
    Name = "${local.prefix}-wg-tg"
  }
}

resource "aws_lb_target_group_attachment" "wireguard" {
  target_group_arn = aws_lb_target_group.wireguard.arn
  target_id        = module.wireguard.private_ip
  port             = local.wireguard_port
}

resource "aws_lb_listener" "wireguard" {
  load_balancer_arn = aws_lb.wireguard.arn
  port              = local.wireguard_port
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wireguard.arn
  }
}
