mod config;
mod grafana;
mod request;
mod validation;

use std::sync::Arc;

use aws_sdk_ssm::Client as SsmClient;
use lambda_runtime::Error;
use reqwest::Client as HttpClient;
use tracing::info;

pub use config::DeployConfig;
pub use request::{DashboardResult, DeployRequest, DeployResponse, PrunedDashboard};

use grafana::GrafanaClient;
use validation::{prepare_dashboard, validate_request};

#[derive(Clone)]
pub struct AppState {
    ssm: SsmClient,
    http: HttpClient,
    config: DeployConfig,
}

impl AppState {
    pub fn new(ssm: SsmClient, http: HttpClient, config: DeployConfig) -> Self {
        Self { ssm, http, config }
    }
}

pub async fn handler(
    request: DeployRequest,
    state: Arc<AppState>,
) -> Result<DeployResponse, Error> {
    validate_request(&request)?;
    let token = grafana_token(&state.ssm, &state.config.token_parameter).await?;
    let client = GrafanaClient::new(
        state.http.clone(),
        state.config.grafana_url.clone(),
        token,
        state.config.namespace.clone(),
    );
    deploy_dashboards(request, &state.config, &client).await
}

async fn deploy_dashboards(
    request: DeployRequest,
    config: &DeployConfig,
    client: &GrafanaClient,
) -> Result<DeployResponse, Error> {
    let repo_tag = config.repo_tag(&request.project);
    let prepared = request
        .dashboards
        .iter()
        .map(|dashboard| {
            prepare_dashboard(
                dashboard,
                &request.project,
                &repo_tag,
                &config.allowed_datasource_uids,
            )
        })
        .collect::<Result<Vec<_>, _>>()?;

    client
        .ensure_folder(&request.folder_uid, &request.folder_title)
        .await?;

    let mut upserted = Vec::new();
    let message = format!("Deploy dashboards for {}", request.project);
    for dashboard in &prepared {
        let result = client
            .upsert_dashboard(dashboard, &request.folder_uid, &message)
            .await?;
        info!(
            project = request.project,
            dashboard_uid = result.uid,
            dashboard_path = result.path,
            "dashboard deployed"
        );
        upserted.push(result);
    }

    let desired_uids = upserted
        .iter()
        .map(|dashboard| dashboard.uid.clone())
        .collect::<Vec<_>>();
    let pruned = if request.prune {
        client
            .prune_dashboards(&request.folder_uid, &repo_tag, &desired_uids)
            .await?
    } else {
        Vec::new()
    };

    Ok(DeployResponse {
        project: request.project,
        folder_uid: request.folder_uid,
        folder_title: request.folder_title,
        upserted,
        pruned,
    })
}

async fn grafana_token(ssm: &SsmClient, parameter_name: &str) -> Result<String, Error> {
    let result = ssm
        .get_parameter()
        .name(parameter_name)
        .with_decryption(true)
        .send()
        .await
        .map_err(|error| {
            std::io::Error::other(format!(
                "SSM read failed for Grafana token parameter {parameter_name}: {error}"
            ))
        })?;

    result
        .parameter()
        .and_then(|parameter| parameter.value())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .ok_or_else(|| {
            std::io::Error::other(format!(
                "Grafana token parameter {parameter_name} has no value"
            ))
            .into()
        })
}
