use ahara_lambda_telemetry::{run_event_lambda, Operation, OperationKind, TelemetryConfig};
use lambda_runtime::{service_fn, Error, LambdaEvent};
use pipeline_status::{record, Event};

#[tokio::main]
async fn main() -> Result<(), Error> {
    let config = aws_config::load_defaults(aws_config::BehaviorVersion::latest()).await;
    let client = aws_sdk_dynamodb::Client::new(&config);
    let registry = std::env::var("REGISTRY_TABLE")?;
    let jobs = std::env::var("JOBS_TABLE")?;
    run_event_lambda(
        TelemetryConfig::new("ahara-pipeline-status"),
        service_fn(move |event: LambdaEvent<Event>| {
            let client = client.clone();
            let registry = registry.clone();
            let jobs = jobs.clone();
            async move {
                Operation::new(
                    TelemetryConfig::new("ahara-pipeline-status"),
                    "pipeline.status",
                )
                .with_kind(OperationKind::Background)
                .observe(record(&client, &registry, &jobs, event.payload))
                .await
            }
        }),
    )
    .await
}
