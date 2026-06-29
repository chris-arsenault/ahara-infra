use std::sync::OnceLock;

use opentelemetry::metrics::{Counter, Histogram};
use opentelemetry::{global, KeyValue};

use crate::{OperationKind, TelemetryConfig};

static OPERATION_COUNT: OnceLock<Counter<u64>> = OnceLock::new();
static OPERATION_DURATION: OnceLock<Histogram<u64>> = OnceLock::new();
static HTTP_COUNT: OnceLock<Counter<u64>> = OnceLock::new();
static HTTP_DURATION: OnceLock<Histogram<u64>> = OnceLock::new();
static LAMBDA_COUNT: OnceLock<Counter<u64>> = OnceLock::new();
static LAMBDA_DURATION: OnceLock<Histogram<u64>> = OnceLock::new();

pub(crate) fn record_operation(
    config: &TelemetryConfig,
    name: &str,
    domain: &str,
    kind: OperationKind,
    outcome: &'static str,
    duration_ms: u128,
) {
    let attrs = operation_attrs(config, name, domain, kind, outcome);
    operation_count().add(1, &attrs);
    operation_duration().record(saturating_u64(duration_ms), &attrs);
}

pub(crate) fn record_http_request(
    config: &TelemetryConfig,
    method: &str,
    path: &str,
    kind: OperationKind,
    status_code: u16,
    duration_ms: u128,
) {
    let attrs = http_attrs(
        config,
        method,
        path,
        kind,
        http_outcome(status_code),
        status_code,
    );
    http_count().add(1, &attrs);
    http_duration().record(saturating_u64(duration_ms), &attrs);
}

pub(crate) fn record_http_error(
    config: &TelemetryConfig,
    method: &str,
    path: &str,
    kind: OperationKind,
    duration_ms: u128,
) {
    let attrs = http_attrs(config, method, path, kind, "failed", 500);
    http_count().add(1, &attrs);
    http_duration().record(saturating_u64(duration_ms), &attrs);
}

pub(crate) fn record_lambda_invocation(
    config: &TelemetryConfig,
    function_name: &str,
    event_type: &str,
    outcome: &'static str,
    duration_ms: u128,
) {
    let attrs = lambda_attrs(config, function_name, event_type, outcome);
    lambda_count().add(1, &attrs);
    lambda_duration().record(saturating_u64(duration_ms), &attrs);
}

pub(crate) fn http_outcome(status_code: u16) -> &'static str {
    if status_code < 400 {
        "succeeded"
    } else if status_code < 500 {
        "rejected"
    } else {
        "failed"
    }
}

fn operation_count() -> &'static Counter<u64> {
    OPERATION_COUNT.get_or_init(|| {
        global::meter("ahara-lambda-telemetry")
            .u64_counter("ahara.operation.count")
            .with_description("Completed Ahara application operations")
            .build()
    })
}

fn operation_duration() -> &'static Histogram<u64> {
    OPERATION_DURATION.get_or_init(|| {
        global::meter("ahara-lambda-telemetry")
            .u64_histogram("ahara.operation.duration_ms")
            .with_description("Ahara application operation duration")
            .with_unit("ms")
            .build()
    })
}

fn http_count() -> &'static Counter<u64> {
    HTTP_COUNT.get_or_init(|| {
        global::meter("ahara-lambda-telemetry")
            .u64_counter("ahara.http.server.request.count")
            .with_description("Completed HTTP requests handled by Ahara Lambdas")
            .build()
    })
}

fn http_duration() -> &'static Histogram<u64> {
    HTTP_DURATION.get_or_init(|| {
        global::meter("ahara-lambda-telemetry")
            .u64_histogram("ahara.http.server.request.duration_ms")
            .with_description("HTTP request duration for Ahara Lambdas")
            .with_unit("ms")
            .build()
    })
}

fn lambda_count() -> &'static Counter<u64> {
    LAMBDA_COUNT.get_or_init(|| {
        global::meter("ahara-lambda-telemetry")
            .u64_counter("ahara.faas.invocation.count")
            .with_description("Completed Ahara Lambda invocations")
            .build()
    })
}

fn lambda_duration() -> &'static Histogram<u64> {
    LAMBDA_DURATION.get_or_init(|| {
        global::meter("ahara-lambda-telemetry")
            .u64_histogram("ahara.faas.invocation.duration_ms")
            .with_description("Ahara Lambda invocation duration")
            .with_unit("ms")
            .build()
    })
}

fn operation_attrs(
    config: &TelemetryConfig,
    name: &str,
    domain: &str,
    kind: OperationKind,
    outcome: &str,
) -> Vec<KeyValue> {
    vec![
        KeyValue::new("service.name", config.service_name().to_string()),
        KeyValue::new("operation.name", name.to_string()),
        KeyValue::new("operation.domain", domain.to_string()),
        KeyValue::new("operation.type", kind.as_str()),
        KeyValue::new("operation.outcome", outcome.to_string()),
    ]
}

fn http_attrs(
    config: &TelemetryConfig,
    method: &str,
    path: &str,
    kind: OperationKind,
    outcome: &str,
    status_code: u16,
) -> Vec<KeyValue> {
    vec![
        KeyValue::new("service.name", config.service_name().to_string()),
        KeyValue::new("http.request.method", method.to_string()),
        KeyValue::new("url.path", path.to_string()),
        KeyValue::new("operation.type", kind.as_str()),
        KeyValue::new("operation.outcome", outcome.to_string()),
        KeyValue::new("http.response.status_code", i64::from(status_code)),
    ]
}

fn lambda_attrs(
    config: &TelemetryConfig,
    function_name: &str,
    event_type: &str,
    outcome: &str,
) -> Vec<KeyValue> {
    vec![
        KeyValue::new("service.name", config.service_name().to_string()),
        KeyValue::new("faas.name", function_name.to_string()),
        KeyValue::new("faas.trigger", event_type.to_string()),
        KeyValue::new("operation.outcome", outcome.to_string()),
    ]
}

fn saturating_u64(value: u128) -> u64 {
    value.min(u128::from(u64::MAX)) as u64
}

#[cfg(test)]
mod tests {
    use super::http_outcome;

    #[test]
    fn http_outcome_separates_success_rejection_and_failure() {
        assert_eq!(http_outcome(200), "succeeded");
        assert_eq!(http_outcome(404), "rejected");
        assert_eq!(http_outcome(500), "failed");
    }
}
