module "project_ahara_observability" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["ahara-observability"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "ahara-observability"
  state_key_prefix = "projects/ahara-observability"

  module_bundles = []

  policy_modules = [
    "komodo-deploy",
    "grafana-dashboard-bootstrap",
  ]

  # This project's parameters are filed under /ahara/observability/, not under
  # its project name. The namespace grant derives from the prefix, so the
  # shorter name has to be named explicitly for the stack to read its own
  # secrets. Refiling them under /ahara/ahara-observability/ would remove this
  # and is the tidier end state.
  truenas_workload_cross_project_parameter_prefixes = ["observability"]
}

# The one container in the observability stack that holds an identity. Every
# application there is a vendor image, so this fetches their secrets and exits
# (ahara-trust ADR-0002). The role grants nothing beyond reading parameters,
# which machine-role derives.
module "ahara_observability_secret_fetch_role" {
  count  = local.ahara_machines_count
  source = "../modules/machine-role"

  prefix                           = "ahara-observability"
  name                             = "secret-fetch"
  cross_project_parameter_prefixes = ["observability"]

  permissions_boundary_arn = module.project_ahara_observability.truenas_workload_boundary_arn
}
