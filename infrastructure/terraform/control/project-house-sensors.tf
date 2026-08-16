module "project_house_sensors" {
  source = "./modules/managed-project"

  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  account_id        = local.account_id

  github_pat         = local.github_pat
  allowed_repos      = ["house-sensors"]
  allowed_branches   = ["main"]
  allow_pull_request = true

  prefix           = "house-sensors"
  state_key_prefix = "projects/house-sensors"

  policy_modules = [
    "terraform-state",
    "komodo-deploy",
    "grafana-dashboard-deploy",
    "s3-private-storage",
    "ssm-write",
  ]

  ssm_additional_parameter_paths = [
    "ahara/house-sensors/*",
    "ahara/machines/workloads/house-sensors/*",
  ]

  # Its collectors write to the household InfluxDB and authenticate to the
  # observability ingest gateway, both of which are that project's parameters.
  # The only cross-project read in the estate.
  truenas_workload_cross_project_parameter_prefixes = ["observability"]
}
