# =============================================================================
# ahara-vpn deployer role
#
# The ahara-vpn repo owns both ends of the WireGuard tunnel: the VP2440 home
# gateway (NixOS, deployed pull-based from the repo itself) and the AWS-side
# endpoint Terraform (WireGuard EC2 instance + pinned ENI, UDP NLB behind
# wg.ahara.io, key and peer-config secrets, published server public key).
# The policy set below covers only that AWS endpoint stack.
# =============================================================================

module "project_ahara_vpn" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["ahara-vpn"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "ahara-vpn"
  state_key_prefix = "projects/ahara-vpn"

  policy_modules = [
    "terraform-state",
    "grafana-dashboard-deploy",
    "ec2-vpc-compute",
    "ec2-security-groups",
    "iam-roles",
    "iam-instance-profiles",
    "alb-loadbalancer",
    "alb-target-group",
    "acm-dns",
    "secrets-manager",
    "ssm-write",
  ]

  ssm_additional_parameter_paths = [
    "ahara/vpn/*",
  ]

  # These secrets were imported into the ahara-vpn state under their existing
  # names so rotating endpoint ownership could not discard either key.
  secrets_manager_additional_secret_arns = [
    "arn:aws:secretsmanager:*:${local.account_id}:secret:ahara-wg-keys-*",
    "arn:aws:secretsmanager:*:${local.account_id}:secret:ahara-network-peer-config-*",
  ]
}
