use std::env;

#[derive(Clone, Debug)]
pub struct BootstrapConfig {
    pub grafana_url: String,
    pub admin_user: String,
    pub admin_password_parameter: String,
    pub token_parameter: String,
    pub service_account_name: String,
    pub service_account_role: String,
    pub token_name: String,
}

impl BootstrapConfig {
    pub fn from_env() -> Self {
        Self {
            grafana_url: env::var("GRAFANA_URL")
                .unwrap_or_else(|_| "http://192.168.66.3:30038".into()),
            admin_user: env::var("GRAFANA_ADMIN_USER").unwrap_or_else(|_| "admin".into()),
            admin_password_parameter: env::var("GRAFANA_ADMIN_PASSWORD_PARAMETER")
                .unwrap_or_else(|_| "/ahara/observability/grafana-admin-password".into()),
            token_parameter: env::var("GRAFANA_TOKEN_PARAMETER")
                .unwrap_or_else(|_| "/ahara/observability/grafana-dashboard-deployer-token".into()),
            service_account_name: env::var("GRAFANA_SERVICE_ACCOUNT_NAME")
                .unwrap_or_else(|_| "ahara-dashboard-deployer".into()),
            service_account_role: env::var("GRAFANA_SERVICE_ACCOUNT_ROLE")
                .unwrap_or_else(|_| "Admin".into()),
            token_name: env::var("GRAFANA_TOKEN_NAME")
                .unwrap_or_else(|_| "ci-dashboard-deployer".into()),
        }
    }
}
