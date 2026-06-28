use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

use lambda_http::Request;

const DEFAULT_MINUTES: i64 = 60;
const MAX_MINUTES: i64 = 24 * 60;
const DEFAULT_EVENT_LIMIT: i32 = 50;
const MAX_EVENT_LIMIT: i32 = 500;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct OpsQuery {
    pub(crate) minutes: i64,
    pub(crate) limit: i32,
    pub(crate) service: Option<String>,
    pub(crate) operation: Option<String>,
    pub(crate) operation_type: Option<String>,
    pub(crate) log_group_prefix: Option<String>,
}

impl OpsQuery {
    pub(crate) fn from_request(request: &Request) -> Result<Self, String> {
        let params = query_params(request);
        Ok(Self {
            minutes: bounded_i64(&params, "minutes", DEFAULT_MINUTES, 1, MAX_MINUTES)?,
            limit: bounded_i32(&params, "limit", DEFAULT_EVENT_LIMIT, 1, MAX_EVENT_LIMIT)?,
            service: optional_param(&params, "service"),
            operation: optional_param(&params, "operation"),
            operation_type: optional_param(&params, "operation_type"),
            log_group_prefix: optional_param(&params, "log_group_prefix"),
        })
    }

    pub(crate) fn start_time(&self) -> i64 {
        epoch_seconds() - (self.minutes * 60)
    }

    pub(crate) fn end_time(&self) -> i64 {
        epoch_seconds()
    }
}

pub(crate) fn operations_query(query: &OpsQuery) -> String {
    [
        "fields @timestamp, `service.name`, `event.name`, `event.domain`, `operation.type`, duration_ms",
        "| filter ispresent(`event.name`)",
        operation_filters(query).as_str(),
        "| stats count(*) as count, avg(duration_ms) as avg_duration_ms, max(duration_ms) as max_duration_ms by `service.name`, `event.name`, `event.domain`, `operation.type`",
        "| sort count desc",
        "| limit 100",
    ]
    .into_iter()
    .filter(|line| !line.is_empty())
    .collect::<Vec<_>>()
    .join("\n")
}

pub(crate) fn events_query(query: &OpsQuery) -> String {
    [
        "fields @timestamp, @message, `service.name`, `event.name`, `event.domain`, `operation.type`, `operation.details`, duration_ms, `http.request.method`, `url.path`, `http.response.status_code`",
        "| filter ispresent(`event.name`)",
        operation_filters(query).as_str(),
        "| sort @timestamp desc",
        format!("| limit {}", query.limit).as_str(),
    ]
    .into_iter()
    .filter(|line| !line.is_empty())
    .collect::<Vec<_>>()
    .join("\n")
}

fn operation_filters(query: &OpsQuery) -> String {
    [
        field_filter("service.name", query.service.as_deref()),
        field_filter("event.name", query.operation.as_deref()),
        field_filter("operation.type", query.operation_type.as_deref()),
    ]
    .into_iter()
    .flatten()
    .collect::<Vec<_>>()
    .join("\n")
}

fn field_filter(field: &'static str, value: Option<&str>) -> Option<String> {
    value.map(|value| format!("| filter `{field}` = {}", logs_literal(value)))
}

fn query_params(request: &Request) -> HashMap<String, String> {
    request
        .uri()
        .query()
        .unwrap_or_default()
        .split('&')
        .filter(|part| !part.is_empty())
        .filter_map(|part| {
            let mut pieces = part.splitn(2, '=');
            let key = decode_component(pieces.next()?);
            let value = decode_component(pieces.next().unwrap_or_default());
            Some((key, value))
        })
        .collect()
}

fn optional_param(params: &HashMap<String, String>, name: &str) -> Option<String> {
    params
        .get(name)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn bounded_i64(
    params: &HashMap<String, String>,
    name: &str,
    default: i64,
    min: i64,
    max: i64,
) -> Result<i64, String> {
    let Some(raw) = optional_param(params, name) else {
        return Ok(default);
    };
    raw.parse::<i64>()
        .map(|value| value.clamp(min, max))
        .map_err(|_| format!("{name} must be an integer"))
}

fn bounded_i32(
    params: &HashMap<String, String>,
    name: &str,
    default: i32,
    min: i32,
    max: i32,
) -> Result<i32, String> {
    let Some(raw) = optional_param(params, name) else {
        return Ok(default);
    };
    raw.parse::<i32>()
        .map(|value| value.clamp(min, max))
        .map_err(|_| format!("{name} must be an integer"))
}

fn decode_component(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => decoded.push(b' '),
            b'%' if index + 2 < bytes.len() => {
                decode_hex_byte(value, index, &mut decoded)
                    .map(|next_index| index = next_index)
                    .unwrap_or_else(|| decoded.push(b'%'));
            }
            byte => decoded.push(byte),
        }
        index += 1;
    }
    String::from_utf8_lossy(&decoded).into_owned()
}

fn decode_hex_byte(value: &str, index: usize, decoded: &mut Vec<u8>) -> Option<usize> {
    let byte = u8::from_str_radix(&value[index + 1..index + 3], 16).ok()?;
    decoded.push(byte);
    Some(index + 2)
}

fn logs_literal(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

fn epoch_seconds() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

#[cfg(test)]
mod tests {
    use lambda_http::{Body, Request};

    use super::{events_query, logs_literal, operations_query, query_params, OpsQuery};

    #[test]
    fn query_params_decode_url_components() {
        let mut request = Request::new(Body::Empty);
        *request.uri_mut() =
            "/api/ops/events?service=linkdrop-api&operation=api.items.get&operation_type=user_interaction"
                .parse()
                .unwrap();

        let params = query_params(&request);

        assert_eq!(params.get("service").unwrap(), "linkdrop-api");
        assert_eq!(params.get("operation").unwrap(), "api.items.get");
    }

    #[test]
    fn query_literals_escape_user_values() {
        assert_eq!(logs_literal("linkdrop\"api"), "\"linkdrop\\\"api\"");
    }

    #[test]
    fn operations_query_filters_by_operation_type() {
        let query = OpsQuery {
            minutes: 60,
            limit: 50,
            service: Some("linkdrop-api".into()),
            operation: None,
            operation_type: Some("polling".into()),
            log_group_prefix: None,
        };

        let built = operations_query(&query);

        assert!(built.contains("`service.name` = \"linkdrop-api\""));
        assert!(built.contains("`operation.type` = \"polling\""));
        assert!(built.contains("stats count(*) as count"));
    }

    #[test]
    fn events_query_limits_result_size() {
        let query = OpsQuery {
            minutes: 15,
            limit: 25,
            service: None,
            operation: Some("api.items.complete_image_upload".into()),
            operation_type: None,
            log_group_prefix: None,
        };

        let built = events_query(&query);

        assert!(built.contains("`event.name` = \"api.items.complete_image_upload\""));
        assert!(built.ends_with("| limit 25"));
    }
}
