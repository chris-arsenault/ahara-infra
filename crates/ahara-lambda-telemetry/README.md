# Ahara Lambda Telemetry

Shared Rust Lambda telemetry for Ahara projects.

The crate standardizes Rust Lambda telemetry on top of `tracing` and
OpenTelemetry. It emits structured JSON logs for CloudWatch debugging and, when
standard OTEL environment variables are configured, exports OTLP traces and
metrics to an OpenTelemetry Collector or compatible vendor/backend.

Ahara dashboards should be built in standard OTEL tooling such as Grafana,
Tempo/Loki/Prometheus, Honeycomb, Datadog, New Relic, or AWS observability
surfaces. Product UIs may link to or summarize that data, but this crate is the
instrumentation contract.

## OTLP Export

OTLP export is disabled by default so a Lambda without a collector does not
spend time failing requests to localhost. It turns on when either the standard
exporter flag or an OTLP endpoint is present:

```text
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
OTEL_EXPORTER_OTLP_ENDPOINT=http://collector:4318
```

Signal-specific endpoint variables such as
`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` and
`OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` and
`OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` are also honored by the upstream OTLP
exporters. Set `OTEL_SDK_DISABLED=true` to force OTEL export off.

## Supported Lambda Shapes

The registered Ahara Rust Lambda repos currently use three entrypoint shapes:

| Shape | Examples | Wrapper |
| ---- | ---- | ---- |
| Legacy `lambda_http::run(axum_router)` | `bookmarker`, `tastebase`, `ahara-business`, `dosekit`, `ahara-access` | Migrate to `ahara-lambda-http` + `run_http_lambda` |
| `lambda_http::run(service_fn(handler))` | `svap`, `tsonu-music`, platform CORS/OG/CI handlers | `run_http_lambda` |
| `lambda_runtime::run(service_fn(handler))` | processing jobs, Cognito trigger, migrations, mail workers, encoders | `run_event_lambda` |

## HTTP Lambda

```rust
use ahara_lambda_http::{default_cors, json_value_response, Route};
use ahara_lambda_telemetry::{run_http_lambda, TelemetryConfig};
use lambda_http::http::{Method, StatusCode};
use lambda_http::{service_fn, Body, Error, Request, Response};

#[tokio::main]
async fn main() -> Result<(), lambda_http::Error> {
    run_http_lambda(
        TelemetryConfig::new("linkdrop-api"),
        service_fn(handle_request),
    )
    .await
}

async fn handle_request(request: Request) -> Result<Response<Body>, Error> {
    let route = Route::from_request(&request);
    let response = if route.is_match(Method::GET, "/health")? {
        json_value_response(StatusCode::OK, serde_json::json!({"status": "ok"}))
    } else {
        json_value_response(StatusCode::NOT_FOUND, serde_json::json!({"message": "not found"}))
    };

    Ok(default_cors(response))
}
```

Every request emits a span, request count metric, request duration histogram,
and JSON completion log with method, sanitized path, response status, outcome,
service identity, deployment environment, and Lambda request ID.

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

Every invocation emits a span, invocation count metric, invocation duration
histogram, and JSON logs with service identity, Lambda request ID, function
metadata, and X-Ray trace ID when available.

## Operation Logging

Use operation wrappers at service/repository/external-call boundaries:

```rust
use ahara_lambda_telemetry::{Operation, OperationKind, TelemetryConfig};

Operation::new(TelemetryConfig::new("linkdrop-processing"), "thumbnail.store")
    .with_domain("archive")
    .with_kind(OperationKind::Background)
    .with_detail("item.id", item_id.to_string())
    .with_detail("object.size", thumbnail_len)
    .observe(async {
        store_thumbnail().await
    })
    .await?;
```

This emits an operation span, operation count metric, operation duration
histogram, and JSON start/finish/error logs with duration, `operation.type`, and
an `operation.details` JSON object. Each operation detail is also flattened onto
the OTEL span as a normal attribute so standard tools can filter and group by
domain fields such as `item.kind`, `image.byte_size`, or `actor.label`.
`operation.type` is one of
`user_interaction`, `polling`, `health`, `background`, or `system`, which lets
dashboards separate update pollers and health checks from direct user work. The
details object is intentionally explicit so private user content is not
accidentally logged; include identifiers, sizes, status values, and booleans,
not raw message bodies, note text, or full private URLs.

## Adoption Check

The package includes `ahara-telemetry-adoption-check`. Run it in CI for repos
that have migrated to this crate:

```bash
cargo run -p ahara-lambda-telemetry --bin ahara-telemetry-adoption-check -- backend
```

It flags direct `tracing_subscriber::fmt()` setup, direct `lambda_http::run` /
`lambda_runtime::run` calls, and Lambda crates that use `run_http_lambda` or
`run_event_lambda` without declaring at least one `Operation` span in the same
Cargo package. Runtime setup belongs in the shared wrappers, and application
work must have an explicit operation boundary so operational logging is not
optional per Lambda.
