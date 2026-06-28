use std::fmt;
use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::Instant;

use lambda_http::tower::Service;
use lambda_http::{Body, IntoResponse, Request, RequestExt, Response};

use crate::{
    init_lambda_logging, HttpRequestErrorEvent, HttpRequestEvent, OperationKind, TelemetryConfig,
    TelemetryLogger, TracingTelemetryLogger,
};

#[derive(Clone, Debug)]
pub struct ObservedHttpService<S, L = TracingTelemetryLogger> {
    inner: S,
    config: TelemetryConfig,
    logger: L,
}

impl<S> ObservedHttpService<S> {
    pub fn new(config: TelemetryConfig, inner: S) -> Self {
        Self {
            inner,
            config,
            logger: TracingTelemetryLogger,
        }
    }
}

impl<S, L> ObservedHttpService<S, L> {
    pub fn with_logger(config: TelemetryConfig, inner: S, logger: L) -> Self {
        Self {
            inner,
            config,
            logger,
        }
    }
}

pub async fn run_http_lambda<'a, R, S, E>(
    config: TelemetryConfig,
    handler: S,
) -> Result<(), lambda_http::Error>
where
    S: Service<Request, Response = R, Error = E>,
    S::Future: Send + 'a + 'static,
    R: IntoResponse + Send + 'static,
    E: fmt::Debug + Into<lambda_runtime::Diagnostic> + Send + 'static,
{
    init_lambda_logging(&config);
    lambda_http::run(ObservedHttpService::new(config, handler)).await
}

impl<S, L, R, E> Service<Request> for ObservedHttpService<S, L>
where
    S: Service<Request, Response = R, Error = E>,
    S::Future: Send + 'static,
    L: TelemetryLogger,
    R: IntoResponse + Send + 'static,
    E: fmt::Debug + Send + 'static,
{
    type Response = Response<Body>;
    type Error = E;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Response, Self::Error>> + Send>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: Request) -> Self::Future {
        let request_context = RequestContext::from_request(&request);
        let future = self.inner.call(request);
        let config = self.config.clone();
        let logger = self.logger.clone();
        Box::pin(async move {
            let started_at = Instant::now();
            match future.await {
                Ok(response) => {
                    let response = response.into_response().await;
                    logger.http_request_finish(HttpRequestEvent {
                        config: &config,
                        request_id: &request_context.request_id,
                        method: &request_context.method,
                        path: &request_context.path,
                        operation_kind: request_context.operation_kind,
                        status_code: response.status().as_u16(),
                        duration_ms: started_at.elapsed().as_millis(),
                    });
                    Ok(response)
                }
                Err(error) => {
                    logger.http_request_error(HttpRequestErrorEvent {
                        config: &config,
                        request_id: &request_context.request_id,
                        method: &request_context.method,
                        path: &request_context.path,
                        operation_kind: request_context.operation_kind,
                        duration_ms: started_at.elapsed().as_millis(),
                        error: &error,
                    });
                    Err(error)
                }
            }
        })
    }
}

#[derive(Debug)]
struct RequestContext {
    request_id: String,
    method: String,
    path: String,
    operation_kind: OperationKind,
}

impl RequestContext {
    fn from_request(request: &Request) -> Self {
        let request_id = request
            .lambda_context_ref()
            .map(|context| context.request_id.clone())
            .unwrap_or_default();
        Self {
            request_id,
            method: request.method().as_str().to_string(),
            path: request.uri().path().to_string(),
            operation_kind: http_operation_kind(request.method().as_str(), request.uri().path()),
        }
    }
}

fn http_operation_kind(method: &str, path: &str) -> OperationKind {
    if path == "/health" || path.ends_with("/health") {
        return OperationKind::Health;
    }
    if method == "GET" && (path.ends_with("/updates") || path.contains("/poll")) {
        return OperationKind::Polling;
    }
    OperationKind::UserInteraction
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;

    use lambda_http::tower::{service_fn, ServiceExt};
    use lambda_http::{Body, Request, Response};

    use super::http_operation_kind;
    use super::ObservedHttpService;
    use crate::{OperationKind, TelemetryConfig};

    #[tokio::test]
    async fn observed_http_service_preserves_response_status() {
        let service = service_fn(|_request: Request| async {
            Ok::<_, Infallible>(
                Response::builder()
                    .status(201)
                    .body(Body::Text("created".to_string()))
                    .unwrap(),
            )
        });

        let response = ObservedHttpService::new(TelemetryConfig::new("test-http"), service)
            .oneshot(Request::new(Body::Empty))
            .await
            .unwrap();

        assert_eq!(response.status().as_u16(), 201);
    }

    #[test]
    fn http_operation_kind_classifies_health_and_polling() {
        assert_eq!(http_operation_kind("GET", "/health"), OperationKind::Health);
        assert_eq!(
            http_operation_kind("GET", "/items/updates"),
            OperationKind::Polling
        );
        assert_eq!(
            http_operation_kind("POST", "/items"),
            OperationKind::UserInteraction
        );
    }
}
