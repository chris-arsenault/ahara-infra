# Ahara Lambda Telemetry

Shared Rust Lambda telemetry for Ahara projects.

The crate standardizes structured JSON logging on top of `tracing` and the
Lambda Rust runtimes. It does not require an OTLP collector. Logs use
OTEL-style field names so CloudWatch entries can be queried consistently today
and exported later without changing call sites.

## Supported Lambda Shapes

The registered Ahara Rust Lambda repos currently use three entrypoint shapes:

| Shape | Examples | Wrapper |
| ---- | ---- | ---- |
| `lambda_http::run(axum_router)` | `bookmarker`, `tastebase`, `ahara-business`, `dosekit`, `agents-of-glass` | `run_http_lambda` |
| `lambda_http::run(service_fn(handler))` | `svap`, `tsonu-music`, platform CORS/OG/CI handlers | `run_http_lambda` |
| `lambda_runtime::run(service_fn(handler))` | processing jobs, Cognito trigger, migrations, mail workers, encoders | `run_event_lambda` |

## HTTP Lambda

```rust
use ahara_lambda_telemetry::{TelemetryConfig, run_http_lambda};

#[tokio::main]
async fn main() -> Result<(), lambda_http::Error> {
    let app = build_router().await?;
    run_http_lambda(TelemetryConfig::new("linkdrop-api"), app).await
}
```

Every request logs method, sanitized path, response status, duration, service
identity, deployment environment, and Lambda request ID.

## Event Lambda

```rust
use ahara_lambda_telemetry::{TelemetryConfig, run_event_lambda};
use lambda_runtime::{Error, LambdaEvent, service_fn};

async fn handler(event: LambdaEvent<serde_json::Value>) -> Result<serde_json::Value, Error> {
    Ok(event.payload)
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    run_event_lambda(TelemetryConfig::new("ahara-auth-trigger"), service_fn(handler)).await
}
```

Every invocation logs start, finish/error, duration, service identity, Lambda
request ID, function metadata, and X-Ray trace ID when available.

## Operation Logging

Use operation wrappers at service/repository/external-call boundaries:

```rust
use ahara_lambda_telemetry::{Operation, TelemetryConfig};

Operation::new(TelemetryConfig::new("linkdrop-processing"), "thumbnail.store")
    .with_domain("archive")
    .observe(async {
        store_thumbnail().await
    })
    .await?;
```

This logs operation start and finish/error with duration. It is intentionally
explicit so private user content is not accidentally logged.

## Adoption Check

The package includes `ahara-telemetry-adoption-check`. Run it in CI for repos
that have migrated to this crate:

```bash
cargo run -p ahara-lambda-telemetry --bin ahara-telemetry-adoption-check -- backend
```

It flags direct `tracing_subscriber::fmt()` setup and direct
`lambda_http::run` / `lambda_runtime::run` calls. Those should move behind this
crate's wrappers so operational logging is not optional per Lambda.
