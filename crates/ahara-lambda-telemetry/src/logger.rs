use std::fmt;
use std::sync::Once;

use tracing_subscriber::fmt::format::FmtSpan;

use crate::TelemetryConfig;

static INIT_LOGGING: Once = Once::new();

pub fn init_lambda_logging(config: &TelemetryConfig) {
    INIT_LOGGING.call_once(|| {
        let filter = tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"));
        let _ = tracing_subscriber::fmt()
            .json()
            .with_env_filter(filter)
            .with_span_events(FmtSpan::CLOSE)
            .try_init();
        TracingTelemetryLogger.startup(config);
    });
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
    pub status_code: u16,
    pub duration_ms: u128,
}

#[derive(Clone, Copy, Debug)]
pub struct HttpRequestErrorEvent<'a> {
    pub config: &'a TelemetryConfig,
    pub request_id: &'a str,
    pub method: &'a str,
    pub path: &'a str,
    pub duration_ms: u128,
    pub error: &'a dyn fmt::Debug,
}

#[derive(Clone, Copy, Debug)]
pub struct OperationEvent<'a> {
    pub config: &'a TelemetryConfig,
    pub name: &'a str,
    pub domain: &'a str,
    pub duration_ms: Option<u128>,
}

#[derive(Clone, Copy, Debug)]
pub struct OperationErrorEvent<'a> {
    pub operation: OperationEvent<'a>,
    pub error: &'a dyn fmt::Debug,
}

impl TelemetryLogger for TracingTelemetryLogger {
    fn startup(&self, config: &TelemetryConfig) {
        tracing::info!(
            event.name = "service.startup",
            event.domain = "runtime",
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
            "lambda invocation started"
        );
    }

    fn lambda_invocation_finish(&self, event: LambdaInvocationEvent<'_>) {
        tracing::info!(
            event.name = "faas.invocation.finish",
            event.domain = "faas",
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
            duration_ms = event.duration_ms.unwrap_or_default(),
            "lambda invocation finished"
        );
    }

    fn lambda_invocation_error(&self, event: LambdaInvocationErrorEvent<'_>) {
        tracing::error!(
            event.name = "faas.invocation.error",
            event.domain = "faas",
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
            duration_ms = event.invocation.duration_ms.unwrap_or_default(),
            error.message = ?event.error,
            "lambda invocation failed"
        );
    }

    fn http_request_finish(&self, event: HttpRequestEvent<'_>) {
        tracing::info!(
            event.name = "http.server.request.finish",
            event.domain = "http",
            service.name = %event.config.service_name(),
            service.version = %event.config.service_version(),
            deployment.environment = %event.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            faas.invocation_id = %event.request_id,
            http.request.method = %event.method,
            url.path = %event.path,
            http.response.status_code = event.status_code,
            duration_ms = event.duration_ms,
            "http request finished"
        );
    }

    fn http_request_error(&self, event: HttpRequestErrorEvent<'_>) {
        tracing::error!(
            event.name = "http.server.request.error",
            event.domain = "http",
            service.name = %event.config.service_name(),
            service.version = %event.config.service_version(),
            deployment.environment = %event.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            faas.invocation_id = %event.request_id,
            http.request.method = %event.method,
            url.path = %event.path,
            duration_ms = event.duration_ms,
            error.message = ?event.error,
            "http request failed"
        );
    }

    fn operation_start(&self, event: OperationEvent<'_>) {
        tracing::info!(
            event.name = %event.name,
            event.domain = %event.domain,
            service.name = %event.config.service_name(),
            service.version = %event.config.service_version(),
            deployment.environment = %event.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            "operation started"
        );
    }

    fn operation_finish(&self, event: OperationEvent<'_>) {
        tracing::info!(
            event.name = %event.name,
            event.domain = %event.domain,
            service.name = %event.config.service_name(),
            service.version = %event.config.service_version(),
            deployment.environment = %event.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            duration_ms = event.duration_ms.unwrap_or_default(),
            "operation finished"
        );
    }

    fn operation_error(&self, event: OperationErrorEvent<'_>) {
        tracing::error!(
            event.name = %event.operation.name,
            event.domain = %event.operation.domain,
            service.name = %event.operation.config.service_name(),
            service.version = %event.operation.config.service_version(),
            deployment.environment = %event.operation.config.deployment_environment(),
            cloud.provider = "aws",
            cloud.platform = "aws_lambda",
            duration_ms = event.operation.duration_ms.unwrap_or_default(),
            error.message = ?event.error,
            "operation failed"
        );
    }
}
