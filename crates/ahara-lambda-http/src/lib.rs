//! Small HTTP helpers for Rust Lambdas that use `lambda_http` directly.
//!
//! This crate intentionally stays below a web framework. It provides the common
//! pieces Ahara Lambda APIs otherwise reach for Axum to get: route matching,
//! path/query/body extraction, JSON responses, public error responses, and CORS
//! response headers.

mod cors;
mod error;
mod extract;
mod response;
mod routing;

pub use cors::{default_cors, CorsConfig};
pub use error::{HttpError, PublicHttpError};
pub use extract::{body_bytes, json_body, query_params};
pub use response::{
    binary_response, empty_response, error_response, json_response, json_value_response,
    message_error_response, no_content_response, private_immutable_cache, text_response,
    with_header,
};
pub use routing::{PathParams, Route, RoutePattern};

pub mod prelude {
    pub use crate::{
        binary_response, body_bytes, default_cors, empty_response, error_response, json_body,
        json_response, json_value_response, message_error_response, no_content_response,
        private_immutable_cache, query_params, text_response, with_header, CorsConfig, HttpError,
        PathParams, PublicHttpError, Route, RoutePattern,
    };
    pub use lambda_http::http::{header, HeaderMap, Method, StatusCode};
    pub use lambda_http::{Body, Request, Response};
}
