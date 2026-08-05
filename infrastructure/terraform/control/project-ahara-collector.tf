# =============================================================================
# ahara-collector deployer role
#
# The ahara-collector repo is the home-LAN IoT collector appliance (NixOS,
# deployed pull-based from the repo itself, the ahara-vpn pattern). It has
# no AWS-side stack: CI only validates the flake and advances the release
# ref, so the role carries state access and nothing else. Grafana dashboard
# deploy gets added when the repo ships dashboards (its backlog).
# =============================================================================

module "project_ahara_collector" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["ahara-collector"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "ahara-collector"
  state_key_prefix = "projects/ahara-collector"

  policy_modules = [
    "terraform-state",
  ]
}
