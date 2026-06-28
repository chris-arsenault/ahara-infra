use std::fmt;
use std::future::Future;
use std::time::Instant;

use crate::{
    OperationErrorEvent, OperationEvent, TelemetryConfig, TelemetryLogger, TracingTelemetryLogger,
};

#[derive(Clone, Debug)]
pub struct Operation {
    config: TelemetryConfig,
    name: &'static str,
    domain: &'static str,
}

impl Operation {
    pub fn new(config: TelemetryConfig, name: &'static str) -> Self {
        Self {
            config,
            name,
            domain: "application",
        }
    }

    pub fn with_domain(mut self, domain: &'static str) -> Self {
        self.domain = domain;
        self
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
    logger.operation_start(OperationEvent {
        config: &operation.config,
        name: operation.name,
        domain: operation.domain,
        duration_ms: None,
    });

    match future.await {
        Ok(value) => {
            logger.operation_finish(OperationEvent {
                config: &operation.config,
                name: operation.name,
                domain: operation.domain,
                duration_ms: Some(started_at.elapsed().as_millis()),
            });
            Ok(value)
        }
        Err(error) => {
            logger.operation_error(OperationErrorEvent {
                operation: OperationEvent {
                    config: &operation.config,
                    name: operation.name,
                    domain: operation.domain,
                    duration_ms: Some(started_at.elapsed().as_millis()),
                },
                error: &error,
            });
            Err(error)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{observe_operation, Operation};
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
}
