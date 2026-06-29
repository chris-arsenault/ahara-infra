use std::fmt;
use std::future::Future;
use std::time::Instant;

use opentelemetry::trace::Status;
use serde_json::{Map, Value};
use tracing::Instrument;
use tracing_opentelemetry::OpenTelemetrySpanExt;

use crate::{
    span_attrs, OperationErrorEvent, OperationEvent, TelemetryConfig, TelemetryLogger,
    TracingTelemetryLogger,
};

pub type OperationDetails = Map<String, Value>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OperationKind {
    UserInteraction,
    Polling,
    Health,
    Background,
    System,
}

impl OperationKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::UserInteraction => "user_interaction",
            Self::Polling => "polling",
            Self::Health => "health",
            Self::Background => "background",
            Self::System => "system",
        }
    }
}

#[derive(Clone, Debug)]
pub struct Operation {
    config: TelemetryConfig,
    name: &'static str,
    domain: &'static str,
    kind: OperationKind,
    details: OperationDetails,
}

impl Operation {
    pub fn new(config: TelemetryConfig, name: &'static str) -> Self {
        Self {
            config,
            name,
            domain: "application",
            kind: OperationKind::UserInteraction,
            details: OperationDetails::new(),
        }
    }

    pub fn with_domain(mut self, domain: &'static str) -> Self {
        self.domain = domain;
        self
    }

    pub fn with_kind(mut self, kind: OperationKind) -> Self {
        self.kind = kind;
        self
    }

    pub fn with_detail(mut self, key: &'static str, value: impl Into<Value>) -> Self {
        self.details.insert(key.to_string(), value.into());
        self
    }

    pub fn with_optional_detail<T>(self, key: &'static str, value: Option<T>) -> Self
    where
        T: Into<Value>,
    {
        match value {
            Some(value) => self.with_detail(key, value),
            None => self,
        }
    }

    pub async fn observe<Fut, T, E>(self, future: Fut) -> Result<T, E>
    where
        Fut: Future<Output = Result<T, E>>,
        E: fmt::Debug,
    {
        observe_operation_with_logger(TracingTelemetryLogger, self, future).await
    }
}

pub async fn observe_operation<Fut, T, E>(
    config: TelemetryConfig,
    name: &'static str,
    future: Fut,
) -> Result<T, E>
where
    Fut: Future<Output = Result<T, E>>,
    E: fmt::Debug,
{
    Operation::new(config, name).observe(future).await
}

pub async fn observe_operation_with_logger<L, Fut, T, E>(
    logger: L,
    operation: Operation,
    future: Fut,
) -> Result<T, E>
where
    L: TelemetryLogger,
    Fut: Future<Output = Result<T, E>>,
    E: fmt::Debug,
{
    let started_at = Instant::now();
    let span = operation_span(&operation);
    logger.operation_start(OperationEvent {
        config: &operation.config,
        name: operation.name,
        domain: operation.domain,
        kind: operation.kind,
        details: &operation.details,
        duration_ms: None,
    });

    match future.instrument(span.clone()).await {
        Ok(value) => {
            span.set_attribute("operation.outcome", "succeeded");
            span.set_status(Status::Ok);
            logger.operation_finish(OperationEvent {
                config: &operation.config,
                name: operation.name,
                domain: operation.domain,
                kind: operation.kind,
                details: &operation.details,
                duration_ms: Some(started_at.elapsed().as_millis()),
            });
            Ok(value)
        }
        Err(error) => {
            span.set_attribute("operation.outcome", "failed");
            span.set_status(Status::error(format!("{error:?}")));
            logger.operation_error(OperationErrorEvent {
                operation: OperationEvent {
                    config: &operation.config,
                    name: operation.name,
                    domain: operation.domain,
                    kind: operation.kind,
                    details: &operation.details,
                    duration_ms: Some(started_at.elapsed().as_millis()),
                },
                error: &error,
            });
            Err(error)
        }
    }
}

fn operation_span(operation: &Operation) -> tracing::Span {
    let span = tracing::info_span!(
        "ahara.operation",
        event.domain = operation.domain,
        operation.name = operation.name,
        operation.type = operation.kind.as_str(),
        operation.domain = operation.domain,
        service.name = operation.config.service_name(),
        service.version = operation.config.service_version(),
        deployment.environment = operation.config.deployment_environment(),
        deployment.environment.name = operation.config.deployment_environment(),
        cloud.provider = "aws",
        cloud.platform = "aws_lambda"
    );
    span.set_attribute("operation.outcome", "started");
    span_attrs::set_operation_details(&span, &operation.details);
    span
}

#[cfg(test)]
mod tests {
    use super::{observe_operation, Operation, OperationKind};
    use crate::TelemetryConfig;

    #[tokio::test]
    async fn operation_observer_returns_successful_value() {
        let result = observe_operation(TelemetryConfig::new("test"), "test.operation", async {
            Ok::<_, String>(7)
        })
        .await
        .unwrap();

        assert_eq!(result, 7);
    }

    #[tokio::test]
    async fn operation_observer_preserves_errors() {
        let err = Operation::new(TelemetryConfig::new("test"), "test.operation")
            .with_domain("test")
            .observe(async { Err::<(), _>("failed".to_string()) })
            .await
            .unwrap_err();

        assert_eq!(err, "failed");
    }

    #[tokio::test]
    async fn operation_observer_accepts_kind_and_details() {
        let result = Operation::new(TelemetryConfig::new("test"), "test.operation")
            .with_domain("test")
            .with_kind(OperationKind::Polling)
            .with_detail("cursor.present", true)
            .with_detail("limit", 25)
            .with_optional_detail("skipped", None::<String>)
            .observe(async { Ok::<_, String>(()) })
            .await;

        assert!(result.is_ok());
    }
}
