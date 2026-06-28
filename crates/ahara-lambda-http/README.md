# Ahara Lambda HTTP

Small helpers for Rust HTTP Lambdas that use `lambda_http` directly.

This crate is intentionally not a web framework. It supplies the pieces Ahara
ALB-backed Lambda APIs commonly used Axum for:

- route matching with named path parameters
- typed JSON body and query-string parsing
- JSON/text/binary response builders
- public error response rendering
- CORS headers for actual responses

## Handler Shape

```rust
use std::sync::Arc;

use ahara_lambda_http::prelude::*;
use lambda_http::{run, service_fn, Error};
use serde::Deserialize;

#[derive(Clone)]
struct AppState;

#[derive(Deserialize)]
struct ListQuery {
    limit: Option<u16>,
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    let state = Arc::new(AppState);
    run(service_fn(move |request| {
        let state = Arc::clone(&state);
        async move { Ok::<_, Error>(handle_request(request, state).await) }
    }))
    .await
}

async fn handle_request(request: Request, state: Arc<AppState>) -> Response<Body> {
    let result = dispatch(&request, state).await;
    default_cors(result.unwrap_or_else(|error| error_response(&error)))
}

async fn dispatch(request: &Request, _state: Arc<AppState>) -> Result<Response<Body>, HttpError> {
    let route = Route::from_request(request);

    if route.is_match(Method::GET, "/health")? {
        return Ok(json_value_response(
            StatusCode::OK,
            serde_json::json!({"status": "ok"}),
        ));
    }

    if route.is_match(Method::GET, "/items")? {
        let query: ListQuery = query_params(request)?;
        return json_response(StatusCode::OK, &serde_json::json!({ "limit": query.limit }));
    }

    if let Some(params) = route.matches(Method::GET, "/items/{item_id}")? {
        let item_id = params.require("item_id")?;
        return json_response(StatusCode::OK, &serde_json::json!({ "id": item_id }));
    }

    Err(HttpError::not_found())
}
```

Pair this crate with `ahara-lambda-telemetry` by passing the `service_fn`
handler through `run_http_lambda` instead of calling `lambda_http::run`
directly.
