use std::fmt;
use std::sync::Once;

use opentelemetry_appender_tracing::layer::OpenTelemetryTracingBridge;
use tracing_subscriber::fmt::format::FmtSpan;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

use crate::{metrics, otel, OperationDetails, OperationKind, TelemetryConfig};

static INIT_LOGGING: Once = Once::new();

pub fn init_lambda_logging(config: &TelemetryConfig) {
    INIT_LOGGING.call_once(|| {
        let providers = Box::leak(Box::new(otel::init_otel(config)));
        let fmt_layer = tracing_subscriber::fmt::layer()
            .json()
            .with_span_events(FmtSpan::CLOSE);
        match (
            providers.tracer_provider.as_ref(),
            providers.logger_provider.as_ref(),
        ) {
            (Some(tracer_provider), Some(logger_provider)) => {
                let tracer = otel::tracer(tracer_provider, config);
                let trace_layer = tracing_opentelemetry::layer().with_tracer(tracer);
                let log_layer = OpenTelemetryTracingBridge::new(logger_provider);
                let _ = tracing_subscriber::registry()
                    .with(env_filter())
                    .with(fmt_layer)
                    .with(trace_layer)
                    .with(log_layer)
                    .try_init();
            }
            (Some(tracer_provider), None) => {
                let tracer = otel::tracer(tracer_provider, config);
                let trace_layer = tracing_opentelemetry::layer().with_tracer(tracer);
                let _ = tracing_subscriber::registry()
                    .with(env_filter())
                    .with(fmt_layer)
                    .with(trace_layer)
                    .try_init();
            }
            (None, Some(logger_provider)) => {
                let log_layer = OpenTelemetryTracingBridge::new(logger_provider);
                let _ = tracing_subscriber::registry()
                    .with(env_filter())
                    .with(fmt_layer)
                    .with(log_layer)
                    .try_init();
            }
            (None, None) => {
                let _ = tracing_subscriber::registry()
                    .with(env_filter())
                    .with(fmt_layer)
                    .try_init();
            }
        }
        let _meter_provider = providers.meter_provider.as_ref();
        TracingTelemetryLogger.startup(config);
    });
}

fn env_filter() -> tracing_subscriber::EnvFilter {
    tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"))
}

pub trait TelemetryLogger: Clone + Send + Sync + 'static {
    fn startup(&self, config: &TelemetryConfig);
    fn lambda_invocation_start(&self, event: LambdaInvocationEvent<'_>);
    fn lambda_invocation_finish(&self, event: LambdaInvocationEvent<'_>);
    fn lambda_invocation_error(&self, event: LambdaInvocationErrorEvent<'_>);
    fn http_request_finish(&self, event: HttpRequestEvent<'_>);
    fn http_request_error(&self, event: HttpRequestErrorEvent<'_>);
    fn operation_start(&self, event: OperationEvent<'_>);
    fn operation_finish(&self, event: OperationEvent<'_>);
    fn operation_error(&self, event: OperationErrorEvent<'_>);
}

#[derive(Clone, Copy, Debug, Default)]
pub struct TracingTelemetryLogger;

#[derive(Clone, Copy, Debug)]
pub struct LambdaInvocationEvent<'a> {
    pub config: &'a TelemetryConfig,
    pub request_id: &'a str,
    pub function_name: &'a str,
    pub function_version: &'a str,
    pub invoked_function_arn: &'a str,
    pub xray_trace_id: Option<&'a str>,
    pub event_type: &'a str,
    pub duration_ms: Option<u128>,
}

#[derive(Clone, Copy, Debug)]
pub struct LambdaInvocationErrorEvent<'a> {
    pub invocation: LambdaInvocationEvent<'a>,
    pub error: &'a dyn fmt::Debug,
}

#[derive(Clone, Copy, Debug)]
pub struct HttpRequestEvent<'a> {
    pub config: &'a TelemetryConfig,
    pub request_id: &'a str,
    pub method: &'a str,
    pub path: &'a str,
    pub operation_kind: OperationKind,
    pub status_code: u16,
    pub duration_ms: u128,
}

#[derive(Clone, Copy, Debug)]
pub struct HttpRequestErrorEvent<'a> {
    pub config: &'a TelemetryConfig,
    pub request_id: &'a str,
    pub method: &'a str,
    pub path: &'a str,
    pub operation_kind: OperationKind,
    pub duration_ms: u128,
    pub error: &'a dyn fmt::Debug,
}

#[derive(Clone, Debug)]
pub struct OperationEvent<'a> {
    pub config: &'a TelemetryConfig,
    pub name: &'a str,
    pub domain: &'a str,
    pub kind: OperationKind,
    pub details: &'a OperationDetails,
    pub duration_ms: Option<u128>,
}

#[derive(Clone, Debug)]
pub struct OperationErrorEvent<'a> {
    pub operation: OperationEvent<'a>,
    pub error: &'a dyn fmt::Debug,
}

impl TelemetryLogger for TracingTelemetryLogger {
    fn startup(&self, config: &TelemetryConfig) {
        tracing::info!(
            event.name = "service.startup",
            event.domain = "runtime",
            event.outcome = "succeeded",
            service.name = %config.service_name(),
            service.version = %config.service_version(),
            deployment.environment = %config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            "service startup"
        );
    }

    fn lambda_invocation_start(&self, event: LambdaInvocationEvent<'_>) {
        tracing::info!(
            event.name = "faas.invocation.start",
            event.domain = "faas",
            event.outcome = "started",
            service.name = %event.config.service_name(),
            service.version = %event.config.service_version(),
            deployment.environment = %event.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            faas.name = %event.function_name,
            faas.version = %event.function_version,
            faas.invocation_id = %event.request_id,
            faas.invoked_arn = %event.invoked_function_arn,
            trace.id = event.xray_trace_id.unwrap_or(""),
            event.type = %event.event_type,
            faas.trigger = %event.event_type,
            "lambda invocation started"
        );
    }

    fn lambda_invocation_finish(&self, event: LambdaInvocationEvent<'_>) {
        let duration_ms = event.duration_ms.unwrap_or_default();
        metrics::record_lambda_invocation(
            event.config,
            event.function_name,
            event.event_type,
            "succeeded",
            duration_ms,
        );
        tracing::info!(
            event.name = "faas.invocation.finish",
            event.domain = "faas",
            event.outcome = "succeeded",
            service.name = %event.config.service_name(),
            service.version = %event.config.service_version(),
            deployment.environment = %event.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            faas.name = %event.function_name,
            faas.version = %event.function_version,
            faas.invocation_id = %event.request_id,
            faas.invoked_arn = %event.invoked_function_arn,
            trace.id = event.xray_trace_id.unwrap_or(""),
            event.type = %event.event_type,
            faas.trigger = %event.event_type,
            duration_ms = duration_ms,
            "lambda invocation finished"
        );
    }

    fn lambda_invocation_error(&self, event: LambdaInvocationErrorEvent<'_>) {
        let duration_ms = event.invocation.duration_ms.unwrap_or_default();
        metrics::record_lambda_invocation(
            event.invocation.config,
            event.invocation.function_name,
            event.invocation.event_type,
            "failed",
            duration_ms,
        );
        tracing::error!(
            event.name = "faas.invocation.error",
            event.domain = "faas",
            event.outcome = "failed",
            service.name = %event.invocation.config.service_name(),
            service.version = %event.invocation.config.service_version(),
            deployment.environment = %event.invocation.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            faas.name = %event.invocation.function_name,
            faas.version = %event.invocation.function_version,
            faas.invocation_id = %event.invocation.request_id,
            faas.invoked_arn = %event.invocation.invoked_function_arn,
            trace.id = event.invocation.xray_trace_id.unwrap_or(""),
            event.type = %event.invocation.event_type,
            faas.trigger = %event.invocation.event_type,
            duration_ms = duration_ms,
            error.message = ?event.error,
            "lambda invocation failed"
        );
    }

    fn http_request_finish(&self, event: HttpRequestEvent<'_>) {
        metrics::record_http_request(
            event.config,
            event.method,
            event.path,
            event.operation_kind,
            event.status_code,
            event.duration_ms,
        );
        tracing::info!(
            event.name = "http.server.request.finish",
            event.domain = "http",
            event.outcome = metrics::http_outcome(event.status_code),
            service.name = %event.config.service_name(),
            service.version = %event.config.service_version(),
            deployment.environment = %event.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            faas.invocation_id = %event.request_id,
            http.request.method = %event.method,
            url.path = %event.path,
            operation.type = %event.operation_kind.as_str(),
            http.response.status_code = event.status_code,
            duration_ms = event.duration_ms,
            "http request finished"
        );
    }

    fn http_request_error(&self, event: HttpRequestErrorEvent<'_>) {
        metrics::record_http_error(
            event.config,
            event.method,
            event.path,
            event.operation_kind,
            event.duration_ms,
        );
        tracing::error!(
            event.name = "http.server.request.error",
            event.domain = "http",
            event.outcome = "failed",
            service.name = %event.config.service_name(),
            service.version = %event.config.service_version(),
            deployment.environment = %event.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            faas.invocation_id = %event.request_id,
            http.request.method = %event.method,
            url.path = %event.path,
            operation.type = %event.operation_kind.as_str(),
            duration_ms = event.duration_ms,
            error.message = ?event.error,
            "http request failed"
        );
    }

    fn operation_start(&self, event: OperationEvent<'_>) {
        tracing::info!(
            event.name = %event.name,
            event.domain = %event.domain,
            event.outcome = "started",
            operation.name = %event.name,
            operation.type = %event.kind.as_str(),
            operation.details = %operation_details_json(event.details),
            service.name = %event.config.service_name(),
            service.version = %event.config.service_version(),
            deployment.environment = %event.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            "operation started"
        );
    }

    fn operation_finish(&self, event: OperationEvent<'_>) {
        let duration_ms = event.duration_ms.unwrap_or_default();
        metrics::record_operation(
            event.config,
            event.name,
            event.domain,
            event.kind,
            "succeeded",
            duration_ms,
        );
        tracing::info!(
            event.name = %event.name,
            event.domain = %event.domain,
            event.outcome = "succeeded",
            operation.name = %event.name,
            operation.type = %event.kind.as_str(),
            operation.details = %operation_details_json(event.details),
            service.name = %event.config.service_name(),
            service.version = %event.config.service_version(),
            deployment.environment = %event.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            duration_ms = duration_ms,
            "operation finished"
        );
    }

    fn operation_error(&self, event: OperationErrorEvent<'_>) {
        let duration_ms = event.operation.duration_ms.unwrap_or_default();
        metrics::record_operation(
            event.operation.config,
            event.operation.name,
            event.operation.domain,
            event.operation.kind,
            "failed",
            duration_ms,
        );
        tracing::error!(
            event.name = %event.operation.name,
            event.domain = %event.operation.domain,
            event.outcome = "failed",
            operation.name = %event.operation.name,
            operation.type = %event.operation.kind.as_str(),
            operation.details = %operation_details_json(event.operation.details),
            service.name = %event.operation.config.service_name(),
            service.version = %event.operation.config.service_version(),
            deployment.environment = %event.operation.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            duration_ms = duration_ms,
            error.message = ?event.error,
            "operation failed"
        );
    }
}

fn operation_details_json(details: &OperationDetails) -> String {
    serde_json::Value::Object(details.clone()).to_string()
}
