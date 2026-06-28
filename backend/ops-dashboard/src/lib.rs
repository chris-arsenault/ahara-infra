mod cloudwatch;
mod query;

use std::env;
use std::sync::Arc;

use aws_sdk_cloudwatchlogs::Client as LogsClient;
use cloudwatch::{execute_logs_query, QueryRow};
use lambda_http::{Body, Error, Request, Response};
use query::{events_query, operations_query, OpsQuery};
use serde::Serialize;
use serde_json::Value;

#[derive(Clone)]
pub struct AppState {
    logs: LogsClient,
    config: DashboardConfig,
}

impl AppState {
    pub fn new(logs: LogsClient, config: DashboardConfig) -> Self {
        Self { logs, config }
    }
}

#[derive(Clone, Debug)]
pub struct DashboardConfig {
    log_group_prefixes: Vec<String>,
    max_log_groups: usize,
    cors_allowed_origin: String,
}

impl DashboardConfig {
    pub fn from_env() -> Self {
        Self {
            log_group_prefixes: env_list("LOG_GROUP_PREFIXES", &["/aws/lambda/"]),
            max_log_groups: env_usize("MAX_LOG_GROUPS", 50),
            cors_allowed_origin: env::var("CORS_ALLOWED_ORIGIN").unwrap_or_else(|_| "*".into()),
        }
    }

    fn log_group_prefixes(&self, query: &OpsQuery) -> Vec<String> {
        query
            .log_group_prefix
            .clone()
            .map(|prefix| vec![prefix])
            .unwrap_or_else(|| self.log_group_prefixes.clone())
    }
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: String,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    ok: bool,
    service: &'static str,
}

#[derive(Debug, Serialize)]
pub struct OperationsResponse {
    minutes: i64,
    log_group_count: usize,
    operations: Vec<OperationSummary>,
}

#[derive(Debug, Serialize)]
pub struct EventsResponse {
    minutes: i64,
    log_group_count: usize,
    events: Vec<OperationLogEvent>,
}

#[derive(Debug, Serialize)]
pub struct OperationSummary {
    service_name: String,
    event_name: String,
    event_domain: String,
    operation_type: String,
    count: i64,
    avg_duration_ms: Option<f64>,
    max_duration_ms: Option<f64>,
}

#[derive(Debug, Serialize)]
pub struct OperationLogEvent {
    timestamp: String,
    service_name: String,
    event_name: String,
    event_domain: String,
    operation_type: String,
    operation_details: Value,
    duration_ms: Option<f64>,
    http_method: String,
    path: String,
    status_code: String,
    message: String,
}

pub async fn handler(request: Request, state: Arc<AppState>) -> Result<Response<Body>, Error> {
    let method = request.method().as_str();
    let path = normalized_path(request.uri().path());
    if method == "OPTIONS" {
        return empty_response(204, &state.config);
    }

    match (method, path.as_str()) {
        ("GET" | "HEAD", "/health") | ("GET" | "HEAD", "/api/ops/health") => health(&state),
        ("GET", "/api/ops/operations") => operations_response(&request, &state).await,
        ("GET", "/api/ops/events") => events_response(&request, &state).await,
        _ => json_response(
            404,
            &ErrorResponse {
                error: "not found".into(),
            },
            &state.config,
        ),
    }
}

fn health(state: &AppState) -> Result<Response<Body>, Error> {
    json_response(
        200,
        &HealthResponse {
            ok: true,
            service: "ops-dashboard",
        },
        &state.config,
    )
}

async fn operations_response(request: &Request, state: &AppState) -> Result<Response<Body>, Error> {
    let query = match OpsQuery::from_request(request) {
        Ok(query) => query,
        Err(error) => return json_response(400, &ErrorResponse { error }, &state.config),
    };
    let result = execute_logs_query(state, &query, operations_query(&query)).await?;
    json_response(
        200,
        &OperationsResponse {
            minutes: query.minutes,
            log_group_count: result.log_group_count,
            operations: result.rows.into_iter().map(operation_summary).collect(),
        },
        &state.config,
    )
}

async fn events_response(request: &Request, state: &AppState) -> Result<Response<Body>, Error> {
    let query = match OpsQuery::from_request(request) {
        Ok(query) => query,
        Err(error) => return json_response(400, &ErrorResponse { error }, &state.config),
    };
    let result = execute_logs_query(state, &query, events_query(&query)).await?;
    json_response(
        200,
        &EventsResponse {
            minutes: query.minutes,
            log_group_count: result.log_group_count,
            events: result.rows.into_iter().map(operation_event).collect(),
        },
        &state.config,
    )
}

fn operation_summary(row: QueryRow) -> OperationSummary {
    OperationSummary {
        service_name: row_string(&row, "service.name"),
        event_name: row_string(&row, "event.name"),
        event_domain: row_string(&row, "event.domain"),
        operation_type: row_string(&row, "operation.type"),
        count: row_i64(&row, "count"),
        avg_duration_ms: row_f64(&row, "avg_duration_ms"),
        max_duration_ms: row_f64(&row, "max_duration_ms"),
    }
}

fn operation_event(row: QueryRow) -> OperationLogEvent {
    OperationLogEvent {
        timestamp: row_string(&row, "@timestamp"),
        service_name: row_string(&row, "service.name"),
        event_name: row_string(&row, "event.name"),
        event_domain: row_string(&row, "event.domain"),
        operation_type: row_string(&row, "operation.type"),
        operation_details: operation_details(&row),
        duration_ms: row_f64(&row, "duration_ms"),
        http_method: row_string(&row, "http.request.method"),
        path: row_string(&row, "url.path"),
        status_code: row_string(&row, "http.response.status_code"),
        message: row_string(&row, "@message"),
    }
}

fn operation_details(row: &QueryRow) -> Value {
    row.get("operation.details")
        .and_then(|details| serde_json::from_str(details).ok())
        .unwrap_or(Value::Null)
}

fn row_string(row: &QueryRow, field: &str) -> String {
    row.get(field).cloned().unwrap_or_default()
}

fn row_i64(row: &QueryRow, field: &str) -> i64 {
    row.get(field)
        .and_then(|value| value.parse::<f64>().ok())
        .map(|value| value as i64)
        .unwrap_or_default()
}

fn row_f64(row: &QueryRow, field: &str) -> Option<f64> {
    row.get(field).and_then(|value| value.parse().ok())
}

fn json_response<T: Serialize>(
    status: u16,
    body: &T,
    config: &DashboardConfig,
) -> Result<Response<Body>, Error> {
    response(status, Body::Text(serde_json::to_string(body)?), config)
}

fn empty_response(status: u16, config: &DashboardConfig) -> Result<Response<Body>, Error> {
    response(status, Body::Text(String::new()), config)
}

fn response(status: u16, body: Body, config: &DashboardConfig) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .header("access-control-allow-origin", &config.cors_allowed_origin)
        .header("access-control-allow-methods", "GET,HEAD,OPTIONS")
        .header("access-control-allow-headers", "authorization,content-type")
        .body(body)?)
}

fn normalized_path(path: &str) -> String {
    if path.len() > 1 {
        path.trim_end_matches('/').to_string()
    } else {
        path.to_string()
    }
}

fn env_list(name: &str, default: &[&str]) -> Vec<String> {
    env::var(name)
        .ok()
        .map(|value| {
            value
                .split(',')
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .filter(|values| !values.is_empty())
        .unwrap_or_else(|| default.iter().map(|value| (*value).to_string()).collect())
}

fn env_usize(name: &str, default: usize) -> usize {
    env::var(name)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(default)
}
