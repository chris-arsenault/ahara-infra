use std::sync::Arc;

use aws_config::BehaviorVersion;
use aws_sdk_cloudwatchlogs::Client as LogsClient;
use lambda_http::{run, service_fn, Error};
use ops_dashboard::{handler, AppState, DashboardConfig};

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .json()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env().add_directive("info".parse()?),
        )
        .without_time()
        .init();

    let aws_config = aws_config::load_defaults(BehaviorVersion::latest()).await;
    let state = Arc::new(AppState::new(
        LogsClient::new(&aws_config),
        DashboardConfig::from_env(),
    ));

    run(service_fn(move |request| {
        let state = Arc::clone(&state);
        async move { handler(request, state).await }
    }))
    .await
}
