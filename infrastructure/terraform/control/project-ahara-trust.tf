# =============================================================================
# ahara-trust deployer role
#
# The ahara-trust repo is the machine-identity appliance (NixOS, deployed
# pull-based from the repo itself, the ahara-vpn pattern). Its CA certificate
# is registered as a Roles Anywhere trust anchor by this control stack, not by
# the project's own CI: granting a project role the ability to create trust
# anchors and IAM roles would let the appliance's deploy path widen its own
# authority. CI here only validates the flake and advances the release ref, so
# the role carries state access and nothing else.
# =============================================================================

module "project_ahara_trust" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["ahara-trust"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "ahara-trust"
  state_key_prefix = "projects/ahara-trust"

  policy_modules = [
    "terraform-state",
  ]
}
