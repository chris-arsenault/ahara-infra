use std::fmt;
use std::future::Future;
use std::pin::Pin;
use std::task::{Context as TaskContext, Poll};
use std::time::Instant;

use lambda_runtime::tower::Service;
use lambda_runtime::{Diagnostic, IntoFunctionResponse, LambdaEvent};
use serde::{Deserialize, Serialize};
use tokio_stream::Stream;

use crate::{
    init_lambda_logging, LambdaInvocationErrorEvent, LambdaInvocationEvent, TelemetryConfig,
    TelemetryLogger, TracingTelemetryLogger,
};

#[derive(Clone, Debug)]
pub struct ObservedEventService<S, L = TracingTelemetryLogger> {
    inner: S,
    config: TelemetryConfig,
    logger: L,
}

impl<S> ObservedEventService<S> {
    pub fn new(config: TelemetryConfig, inner: S) -> Self {
        Self {
            inner,
            config,
            logger: TracingTelemetryLogger,
        }
    }
}

impl<S, L> ObservedEventService<S, L> {
    pub fn with_logger(config: TelemetryConfig, inner: S, logger: L) -> Self {
        Self {
            inner,
            config,
            logger,
        }
    }
}

pub async fn run_event_lambda<A, Handler, Response, Body, StreamBody, StreamData, StreamError>(
    config: TelemetryConfig,
    handler: Handler,
) -> Result<(), lambda_runtime::Error>
where
    ObservedEventService<Handler>: Service<LambdaEvent<A>, Response = Response>,
    <ObservedEventService<Handler> as Service<LambdaEvent<A>>>::Future: Future<
        Output = Result<
            Response,
            <ObservedEventService<Handler> as Service<LambdaEvent<A>>>::Error,
        >,
    >,
    <ObservedEventService<Handler> as Service<LambdaEvent<A>>>::Error:
        Into<Diagnostic> + fmt::Debug,
    A: for<'de> Deserialize<'de> + Send + 'static,
    Response: IntoFunctionResponse<Body, StreamBody>,
    Body: Serialize,
    StreamBody: Stream<Item = Result<StreamData, StreamError>> + Unpin + Send + 'static,
    StreamData: Into<bytes::Bytes> + Send,
    StreamError: Into<lambda_runtime::Error> + Send + fmt::Debug,
{
    init_lambda_logging(&config);
    lambda_runtime::run(ObservedEventService::new(config, handler)).await
}

impl<S, L, A, R> Service<LambdaEvent<A>> for ObservedEventService<S, L>
where
    S: Service<LambdaEvent<A>, Response = R>,
    S::Future: Send + 'static,
    S::Error: fmt::Debug + Send + 'static,
    L: TelemetryLogger,
    A: Send + 'static,
    R: Send + 'static,
{
    type Response = R;
    type Error = S::Error;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>> + Send>>;

    fn poll_ready(&mut self, cx: &mut TaskContext<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, event: LambdaEvent<A>) -> Self::Future {
        let event_context = EventContext::from_event::<A>(&event);
        let future = self.inner.call(event);
        let config = self.config.clone();
        let logger = self.logger.clone();
        Box::pin(async move {
            let started_at = Instant::now();
            logger.lambda_invocation_start(LambdaInvocationEvent {
                config: &config,
                request_id: &event_context.request_id,
                function_name: &event_context.function_name,
                function_version: &event_context.function_version,
                invoked_function_arn: &event_context.invoked_function_arn,
                xray_trace_id: event_context.xray_trace_id.as_deref(),
                event_type: event_context.event_type,
                duration_ms: None,
            });

            match future.await {
                Ok(response) => {
                    logger.lambda_invocation_finish(LambdaInvocationEvent {
                        config: &config,
                        request_id: &event_context.request_id,
                        function_name: &event_context.function_name,
                        function_version: &event_context.function_version,
                        invoked_function_arn: &event_context.invoked_function_arn,
                        xray_trace_id: event_context.xray_trace_id.as_deref(),
                        event_type: event_context.event_type,
                        duration_ms: Some(started_at.elapsed().as_millis()),
                    });
                    Ok(response)
                }
                Err(error) => {
                    logger.lambda_invocation_error(LambdaInvocationErrorEvent {
                        invocation: LambdaInvocationEvent {
                            config: &config,
                            request_id: &event_context.request_id,
                            function_name: &event_context.function_name,
                            function_version: &event_context.function_version,
                            invoked_function_arn: &event_context.invoked_function_arn,
                            xray_trace_id: event_context.xray_trace_id.as_deref(),
                            event_type: event_context.event_type,
                            duration_ms: Some(started_at.elapsed().as_millis()),
                        },
                        error: &error,
                    });
                    Err(error)
                }
            }
        })
    }
}

#[derive(Debug)]
struct EventContext {
    request_id: String,
    function_name: String,
    function_version: String,
    invoked_function_arn: String,
    xray_trace_id: Option<String>,
    event_type: &'static str,
}

impl EventContext {
    fn from_event<A>(event: &LambdaEvent<A>) -> Self {
        Self {
            request_id: event.context.request_id.clone(),
            function_name: event.context.env_config.function_name.clone(),
            function_version: event.context.env_config.version.clone(),
            invoked_function_arn: event.context.invoked_function_arn.clone(),
            xray_trace_id: event.context.xray_trace_id.clone(),
            event_type: std::any::type_name::<A>(),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;

    use lambda_runtime::tower::{service_fn, ServiceExt};
    use lambda_runtime::{Context, LambdaEvent};
    use serde_json::{json, Value};

    use super::ObservedEventService;
    use crate::TelemetryConfig;

    #[tokio::test]
    async fn observed_event_service_preserves_successful_response() {
        let service =
            service_fn(
                |event: LambdaEvent<Value>| async move { Ok::<_, Infallible>(event.payload) },
            );
        let event = LambdaEvent::new(json!({ "ok": true }), Context::default());

        let response = ObservedEventService::new(TelemetryConfig::new("test-event"), service)
            .oneshot(event)
            .await
            .unwrap();

        assert_eq!(response, json!({ "ok": true }));
    }
}
