# =============================================================================
# ALB listener rule that authenticates reverse-proxy traffic via Cognito.
#
# Lives here (not in network/) so it can reference the Cognito pool and ALB
# client directly without going through /ahara/cognito/* SSM data sources.
# Attaches to the shared ALB listener via var.alb_listener_arn.
# =============================================================================

resource "aws_lb_listener_rule" "reverse_proxy_authenticated" {
  count        = length(var.reverse_proxy_cognito_hosts) > 0 ? 1 : 0
  listener_arn = var.alb_listener_arn
  priority     = 100

  condition {
    host_header {
      values = var.reverse_proxy_cognito_hosts
    }
  }

  action {
    type  = "authenticate-cognito"
    order = 1

    authenticate_cognito {
      user_pool_arn              = module.cognito.user_pool_arn
      user_pool_client_id        = aws_cognito_user_pool_client.alb.id
      user_pool_domain           = module.cognito.domain_name
      on_unauthenticated_request = "authenticate"
      scope                      = "openid email profile"
      session_cookie_name        = "${local.prefix}-alb-auth"
      session_timeout            = 3600
    }
  }

  action {
    type             = "forward"
    order            = 2
    target_group_arn = var.reverse_proxy_target_group_arn
  }
}
