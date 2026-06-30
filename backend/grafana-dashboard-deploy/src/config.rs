use std::collections::BTreeSet;
use std::env;

#[derive(Clone, Debug)]
pub struct DeployConfig {
    pub grafana_url: String,
    pub token_parameter: String,
    pub allowed_datasource_uids: BTreeSet<String>,
    pub managed_tag_prefix: String,
}

impl DeployConfig {
    pub fn from_env() -> Self {
        Self {
            grafana_url: env::var("GRAFANA_URL")
                .unwrap_or_else(|_| "http://192.168.66.3:30038".into()),
            token_parameter: env::var("GRAFANA_TOKEN_PARAMETER")
                .unwrap_or_else(|_| "/ahara/observability/grafana-dashboard-deployer-token".into()),
            allowed_datasource_uids: env_list("GRAFANA_ALLOWED_DATASOURCE_UIDS"),
            managed_tag_prefix: env::var("GRAFANA_MANAGED_TAG_PREFIX")
                .unwrap_or_else(|_| "ahara:repo:".into()),
        }
    }

    pub fn repo_tag(&self, project: &str) -> String {
        format!("{}{project}", self.managed_tag_prefix)
    }
}

fn env_list(name: &str) -> BTreeSet<String> {
    env::var(name)
        .ok()
        .into_iter()
        .flat_map(|value| {
            value
                .split(',')
                .map(str::trim)
                .filter(|part| !part.is_empty())
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .collect()
}
