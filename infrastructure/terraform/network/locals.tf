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
      port    = 30038
      auth    = "passthrough"
    }
    "sonar.services.ahara.io" = {
      address       = "192.168.66.3"
      port          = 30090
      auth          = "passthrough"
      max_body_size = "5m"
    }
    "api.airwave.ahara.io" = {
      address   = "192.168.66.3"
      port      = 7882
      auth      = "internal"
      buffering = "off"
    }
  }
  truenas_observability_host   = "192.168.66.3"
  truenas_loki_port            = 3100
  truenas_otlp_grpc_port       = 4317
  truenas_otlp_http_port       = 4318
  truenas_victoriametrics_port = 8428
  # Where the WireGuard host writes its wg-metrics-textfile.sh output; read by
  # Alloy's prometheus.exporter.unix textfile block on that host only.
  #
  # Deliberately NOT under /var/lib/alloy: pre-creating a path there before the
  # alloy RPM's own useradd step runs leaves /var/lib/alloy root-owned, and the
  # postinstall skips fixing ownership on an already-existing home directory --
  # the alloy user then fails to chdir into its own working directory at start
  # (CHDIR/Permission denied, crash-loops until systemd gives up). Using an
  # independent path this script fully owns avoids depending on the alloy
  # package's internal directory layout entirely.
  wg_textfile_dir = "/var/lib/wg-metrics/textfile"
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  az              = local.azs[0]
  az_secondary    = local.azs[1]
  # Hosts with auth = "internal" are nginx upstreams only. Their ALB
  # listener/cert/DNS is owned by project Terraform (e.g. alb-api-truenas), but
  # they still use this route map for reverse-proxy config and scoped SG ingress.
  reverse_proxy_internal_hosts    = sort([for h, r in local.reverse_proxy_routes : h if try(r.auth, "") == "internal"])
  reverse_proxy_hostnames         = sort([for h, r in local.reverse_proxy_routes : h if !contains(["internal"], try(r.auth, ""))])
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
