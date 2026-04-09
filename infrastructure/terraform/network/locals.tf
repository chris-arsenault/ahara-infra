data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_route53_zone" "root" {
  name         = "ahara.io."
  private_zone = false
}

locals {
  prefix                 = "ahara"
  root_domain_name       = "ahara.io"
  wireguard_port         = 51820
  wireguard_cidr         = "10.200.0.0/24"
  wireguard_cidr_host    = "10.200.0.1/24"
  vpc_cidr               = "10.42.0.0/16"
  public_subnet_cidr     = "10.42.10.0/24"
  public_subnet_cidr_b   = "10.42.11.0/24"
  private_subnet_cidr    = "10.42.20.0/24"
  private_subnet_cidr_b  = "10.42.21.0/24"
  allowed_cidrs          = ["0.0.0.0/0"]
  allowed_ipv6_cidrs     = []
  laptop_peer_public_key = ""
  ssm_public_key_path    = "/${local.prefix}/server_public_key"
  home_peer_address      = format("%s/32", cidrhost(local.wireguard_cidr, 2))
  # Reverse proxy hostnames live under services.ahara.io (not the apex),
  # keeping the apex zone free for ahara-portal to own.
  reverse_proxy_routes = {
    "dashboards.services.ahara.io" = {
      address = "192.168.66.3"
      port    = 30037
      auth    = "cognito"
    }
    "sonar.services.ahara.io" = {
      address       = "192.168.66.3"
      port          = 30090
      auth          = "passthrough"
      max_body_size = "5m"
    }
  }
  azs                             = slice(data.aws_availability_zones.available.names, 0, 2)
  az                              = local.azs[0]
  az_secondary                    = local.azs[1]
  reverse_proxy_hostnames         = sort(keys(local.reverse_proxy_routes))
  reverse_proxy_cognito_hosts     = [for h, r in local.reverse_proxy_routes : h if r.auth == "cognito"]
  reverse_proxy_passthrough_hosts = [for h, r in local.reverse_proxy_routes : h if r.auth == "passthrough"]
  reverse_proxy_primary_hostname  = local.reverse_proxy_hostnames[0]
  reverse_proxy_sans              = [for host in local.reverse_proxy_hostnames : host if host != local.reverse_proxy_primary_hostname]
  route53_zone_id                 = data.aws_route53_zone.root.zone_id
  hardening_dnf_config            = templatefile("${path.module}/templates/dnf_automatic.conf.tpl", {})
  hardening_sysctl_config         = templatefile("${path.module}/templates/sysctl_hardening.conf.tpl", {})
  hardening_aide_config           = templatefile("${path.module}/templates/aide_amazon_linux.conf.tpl", {})
  hardening_script = templatefile("${path.module}/templates/apply_system_hardening.sh.tpl", {
    DNF_AUTOMATIC_CONF     = local.hardening_dnf_config
    SYSCTL_HARDENING_CONF  = local.hardening_sysctl_config
    AIDE_AMAZON_LINUX_CONF = local.hardening_aide_config
  })
  vector_service_override = templatefile("${path.module}/templates/vector_service_override.conf.tpl", {})
  vector_service_unit     = templatefile("${path.module}/templates/vector.service.tpl", {})
}
