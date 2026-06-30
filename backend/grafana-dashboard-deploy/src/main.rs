use std::sync::Arc;

use aws_config::BehaviorVersion;
use aws_sdk_ssm::Client as SsmClient;
use grafana_dashboard_deploy::{handler, AppState, DeployConfig, DeployRequest};
use lambda_runtime::{run, service_fn, Error, LambdaEvent};
use reqwest::Client as HttpClient;

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt().json().init();

    let aws_config = aws_config::load_defaults(BehaviorVersion::latest()).await;
    let state = Arc::new(AppState::new(
        SsmClient::new(&aws_config),
        HttpClient::new(),
        DeployConfig::from_env(),
    ));

    run(service_fn(|event: LambdaEvent<DeployRequest>| {
        let state = Arc::clone(&state);
        async move { handler(event.payload, state).await }
    }))
    .await
}
