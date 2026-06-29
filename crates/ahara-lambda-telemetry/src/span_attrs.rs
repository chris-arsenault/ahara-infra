use serde_json::Value as JsonValue;
use tracing::Span;
use tracing_opentelemetry::OpenTelemetrySpanExt;

use crate::OperationDetails;

pub(crate) fn set_operation_details(span: &Span, details: &OperationDetails) {
    for (key, value) in details {
        set_json_attribute(span, key, value);
    }
}

fn set_json_attribute(span: &Span, key: &str, value: &JsonValue) {
    match value {
        JsonValue::Bool(value) => span.set_attribute(key.to_string(), *value),
        JsonValue::Number(value) => set_number_attribute(span, key, value),
        JsonValue::String(value) => span.set_attribute(key.to_string(), value.clone()),
        JsonValue::Array(_) | JsonValue::Object(_) => {
            span.set_attribute(key.to_string(), value.to_string());
        }
        JsonValue::Null => {}
    }
}

fn set_number_attribute(span: &Span, key: &str, value: &serde_json::Number) {
    if let Some(value) = value.as_i64() {
        span.set_attribute(key.to_string(), value);
    } else if let Some(value) = value.as_u64() {
        span.set_attribute(key.to_string(), value.min(i64::MAX as u64) as i64);
    } else if let Some(value) = value.as_f64() {
        span.set_attribute(key.to_string(), value);
    }
}
