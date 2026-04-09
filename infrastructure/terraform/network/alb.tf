resource "aws_lb" "reverse_proxy" {
  name               = "${local.prefix}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets = [
    aws_subnet.public.id,
    aws_subnet.public_b.id
  ]

  enable_deletion_protection = false

  tags = {
    Name      = "${local.prefix}-alb"
    "lb:role" = "ahara"
  }
}

resource "aws_lb_target_group" "reverse_proxy" {
  name        = "${local.prefix}-proxy-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    path                = "/"
    matcher             = "200-399"
  }

  tags = {
    Name = "${local.prefix}-proxy-tg"
  }
}

resource "aws_lb_target_group_attachment" "reverse_proxy_instance" {
  target_group_arn = aws_lb_target_group.reverse_proxy.arn
  target_id        = module.reverse_proxy.private_ip
  port             = 80
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.reverse_proxy.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.reverse_proxy.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.reverse_proxy.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  depends_on = [aws_acm_certificate_validation.reverse_proxy]
}

# Note: the Cognito-authenticated listener rule (priority 100) lives in
# services/cognito-listener.tf so it can reference the Cognito pool directly
# without cross-state SSM lookups. It attaches to this same listener via the
# alb_listener_arn module output.

# --- Reverse proxy: passthrough routes (services handle their own auth) ---

resource "aws_lb_listener_rule" "reverse_proxy_passthrough" {
  count        = length(local.reverse_proxy_passthrough_hosts) > 0 ? 1 : 0
  listener_arn = aws_lb_listener.https.arn
  priority     = 101

  condition {
    host_header {
      values = local.reverse_proxy_passthrough_hosts
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.reverse_proxy.arn
  }
}
