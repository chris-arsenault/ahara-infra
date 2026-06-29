use std::fmt;
use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::Instant;

use lambda_http::http::HeaderMap;
use lambda_http::tower::Service;
use lambda_http::{Body, IntoResponse, Request, RequestExt, Response};
use opentelemetry::global;
use opentelemetry::propagation::Extractor;
use opentelemetry::trace::Status;
use tracing::Instrument;
use tracing_opentelemetry::OpenTelemetrySpanExt;

use crate::{
    init_lambda_logging, metrics, HttpRequestErrorEvent, HttpRequestEvent, OperationKind,
    TelemetryConfig, TelemetryLogger, TracingTelemetryLogger,
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
        let span = request_span(&request_context);
        let _ = span.set_parent(request_parent_context(request.headers()));
        let future = self.inner.call(request).instrument(span.clone());
        let config = self.config.clone();
        let logger = self.logger.clone();
        Box::pin(async move {
            let started_at = Instant::now();
            match future.await {
                Ok(response) => {
                    let response = response.into_response().await;
                    let status_code = response.status().as_u16();
                    span.set_attribute("http.response.status_code", i64::from(status_code));
                    span.set_attribute("operation.outcome", metrics::http_outcome(status_code));
                    if status_code >= 500 {
                        span.set_status(Status::error(format!("HTTP {status_code}")));
                    } else if status_code < 400 {
                        span.set_status(Status::Ok);
                    }
                    logger.http_request_finish(HttpRequestEvent {
                        config: &config,
                        request_id: &request_context.request_id,
                        method: &request_context.method,
                        path: &request_context.path,
                        operation_kind: request_context.operation_kind,
                        status_code,
                        duration_ms: started_at.elapsed().as_millis(),
                    });
                    Ok(response)
                }
                Err(error) => {
                    span.set_attribute("operation.outcome", "failed");
                    span.set_status(Status::error(format!("{error:?}")));
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
            path: sanitized_path(request.uri().path()),
            operation_kind: http_operation_kind(request.method().as_str(), request.uri().path()),
        }
    }
}

struct HeaderExtractor<'a>(&'a HeaderMap);

impl Extractor for HeaderExtractor<'_> {
    fn get(&self, key: &str) -> Option<&str> {
        self.0.get(key).and_then(|value| value.to_str().ok())
    }

    fn keys(&self) -> Vec<&str> {
        self.0.keys().map(|key| key.as_str()).collect()
    }
}

fn request_parent_context(headers: &HeaderMap) -> opentelemetry::Context {
    global::get_text_map_propagator(|propagator| propagator.extract(&HeaderExtractor(headers)))
}

fn request_span(request: &RequestContext) -> tracing::Span {
    let span = tracing::info_span!(
        "http.server.request",
        event.domain = "http",
        event.name = "http.server.request",
        http.request.method = request.method.as_str(),
        url.path = request.path.as_str(),
        operation.type = request.operation_kind.as_str(),
        faas.invocation_id = request.request_id.as_str()
    );
    span.set_attribute("operation.outcome", "started");
    span
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

fn sanitized_path(path: &str) -> String {
    path.split('/')
        .map(sanitized_path_segment)
        .collect::<Vec<_>>()
        .join("/")
}

fn sanitized_path_segment(segment: &str) -> &str {
    if !segment.is_empty()
        && (looks_like_uuid(segment) || segment.chars().all(|ch| ch.is_ascii_digit()))
    {
        "{id}"
    } else {
        segment
    }
}

fn looks_like_uuid(value: &str) -> bool {
    value.len() == 36 && value.chars().all(|ch| ch.is_ascii_hexdigit() || ch == '-')
}

#[cfg(test)]
mod tests {
    use std::convert::Infallible;

    use lambda_http::tower::{service_fn, ServiceExt};
    use lambda_http::{Body, Request, Response};

    use super::ObservedHttpService;
    use super::{http_operation_kind, sanitized_path};
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

    #[test]
    fn sanitized_path_replaces_high_cardinality_ids() {
        assert_eq!(
            sanitized_path("/items/550e8400-e29b-41d4-a716-446655440000/image"),
            "/items/{id}/image"
        );
        assert_eq!(sanitized_path("/items/123"), "/items/{id}");
    }
}
