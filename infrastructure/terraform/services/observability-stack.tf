resource "random_password" "observability_grafana_admin" {
  length  = 32
  special = false
}

resource "random_password" "observability_grafana_secret_key" {
  length  = 48
  special = false
}

resource "random_password" "observability_influxdb_admin" {
  length  = 32
  special = false
}

resource "random_password" "observability_influxdb_token" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "observability_grafana_admin_password" {
  name  = "${local.ssm_prefix}/observability/grafana-admin-password"
  type  = "SecureString"
  value = random_password.observability_grafana_admin.result
}

resource "aws_ssm_parameter" "observability_grafana_secret_key" {
  name  = "${local.ssm_prefix}/observability/grafana-secret-key"
  type  = "SecureString"
  value = random_password.observability_grafana_secret_key.result
}

resource "aws_ssm_parameter" "observability_influxdb_admin_password" {
  name  = "${local.ssm_prefix}/observability/influxdb-admin-password"
  type  = "SecureString"
  value = random_password.observability_influxdb_admin.result
}

resource "aws_ssm_parameter" "observability_influxdb_admin_token" {
  name  = "${local.ssm_prefix}/observability/influxdb-admin-token"
  type  = "SecureString"
  value = random_password.observability_influxdb_token.result
}
