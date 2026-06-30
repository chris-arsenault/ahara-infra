mod config;
mod grafana;
mod request;
mod ssm;

use std::sync::Arc;

use aws_sdk_ssm::Client as SsmClient;
use lambda_runtime::Error;
use reqwest::Client as HttpClient;
use tracing::{error, info};

pub use config::BootstrapConfig;
pub use request::{BootstrapRequest, BootstrapResponse};

use grafana::GrafanaAdminClient;
use ssm::{read_secure_parameter, write_secure_parameter};

#[derive(Clone)]
pub struct AppState {
    ssm: SsmClient,
    http: HttpClient,
    config: BootstrapConfig,
}

impl AppState {
    pub fn new(ssm: SsmClient, http: HttpClient, config: BootstrapConfig) -> Self {
        Self { ssm, http, config }
    }
}

pub async fn handler(
    request: BootstrapRequest,
    state: Arc<AppState>,
) -> Result<BootstrapResponse, Error> {
    match request.action.as_str() {
        "bootstrap-dashboard-deployer-token" => bootstrap(state).await,
        action => {
            let message = format!("Unknown action: {action}");
            error!(
                error = message,
                "Grafana dashboard bootstrap rejected request"
            );
            Ok(BootstrapResponse::failure(message))
        }
    }
}

async fn bootstrap(state: Arc<AppState>) -> Result<BootstrapResponse, Error> {
    let config = &state.config;
    info!(
        grafana_url = config.grafana_url,
        service_account = config.service_account_name,
        token_parameter = config.token_parameter,
        "Grafana dashboard bootstrap starting"
    );

    let admin_password = read_secure_parameter(
        &state.ssm,
        &config.admin_password_parameter,
        "Grafana admin password",
    )
    .await?;
    let grafana = GrafanaAdminClient::new(
        state.http.clone(),
        config.grafana_url.clone(),
        config.admin_user.clone(),
        admin_password,
    );

    grafana.wait_for_health().await?;
    let account = grafana
        .ensure_service_account(&config.service_account_name, &config.service_account_role)
        .await?;
    let token = grafana
        .rotate_named_token(account.id, &config.token_name)
        .await?;
    write_secure_parameter(&state.ssm, &config.token_parameter, &token).await?;

    info!(
        service_account_id = account.id,
        token_parameter = config.token_parameter,
        "Grafana dashboard deployer token stored in SSM"
    );

    Ok(BootstrapResponse::success(
        account.id,
        config.token_parameter.clone(),
    ))
}
