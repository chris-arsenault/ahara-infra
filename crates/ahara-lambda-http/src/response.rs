use lambda_http::http::header::{CACHE_CONTROL, CONTENT_TYPE};
use lambda_http::http::{HeaderName, HeaderValue, StatusCode};
use lambda_http::{Body, Response};
use serde::Serialize;
use serde_json::json;

use crate::error::{HttpError, PublicHttpError};

pub fn json_response<T: Serialize>(
    status: StatusCode,
    value: &T,
) -> Result<Response<Body>, HttpError> {
    let body = serde_json::to_string(value)
        .map_err(|_| HttpError::internal("failed to serialize response body"))?;
    response_with_body(status, "application/json", Body::Text(body))
}

pub fn json_value_response(status: StatusCode, value: serde_json::Value) -> Response<Body> {
    response_with_body(status, "application/json", Body::Text(value.to_string()))
        .expect("valid JSON response")
}

pub fn text_response(
    status: StatusCode,
    content_type: impl AsRef<str>,
    body: impl Into<String>,
) -> Result<Response<Body>, HttpError> {
    response_with_body(status, content_type, Body::Text(body.into()))
}

pub fn binary_response(
    status: StatusCode,
    content_type: impl AsRef<str>,
    bytes: impl Into<Vec<u8>>,
) -> Result<Response<Body>, HttpError> {
    response_with_body(status, content_type, Body::Binary(bytes.into()))
}

pub fn empty_response(status: StatusCode) -> Response<Body> {
    Response::builder()
        .status(status)
        .body(Body::Empty)
        .expect("valid empty response")
}

pub fn no_content_response() -> Response<Body> {
    empty_response(StatusCode::NO_CONTENT)
}

pub fn error_response(error: &impl PublicHttpError) -> Response<Body> {
    json_value_response(
        error.status_code(),
        json!({
            "code": error.code(),
            "message": error.message(),
        }),
    )
}

pub fn message_error_response(status: StatusCode, message: impl Into<String>) -> Response<Body> {
    json_value_response(status, json!({ "message": message.into() }))
}

pub fn with_header(
    mut response: Response<Body>,
    name: HeaderName,
    value: impl AsRef<str>,
) -> Result<Response<Body>, HttpError> {
    response
        .headers_mut()
        .insert(name, header_value(value.as_ref())?);
    Ok(response)
}

pub fn private_immutable_cache(mut response: Response<Body>) -> Response<Body> {
    response.headers_mut().insert(
        CACHE_CONTROL,
        HeaderValue::from_static("private, max-age=31536000, immutable"),
    );
    response
}

fn response_with_body(
    status: StatusCode,
    content_type: impl AsRef<str>,
    body: Body,
) -> Result<Response<Body>, HttpError> {
    Response::builder()
        .status(status)
        .header(CONTENT_TYPE, header_value(content_type.as_ref())?)
        .body(body)
        .map_err(|_| HttpError::internal("failed to build response"))
}

fn header_value(value: &str) -> Result<HeaderValue, HttpError> {
    HeaderValue::from_str(value).map_err(|_| HttpError::internal("invalid response header value"))
}

#[cfg(test)]
mod tests {
    use lambda_http::http::StatusCode;
    use lambda_http::Body;
    use serde::Serialize;

    use super::{error_response, json_response};
    use crate::HttpError;

    #[derive(Serialize)]
    struct Payload {
        ok: bool,
    }

    #[test]
    fn json_response_sets_content_type_and_body() {
        let response = json_response(StatusCode::CREATED, &Payload { ok: true }).unwrap();

        assert_eq!(response.status(), StatusCode::CREATED);
        assert_eq!(
            response.headers().get("content-type").unwrap(),
            "application/json"
        );
        assert_eq!(response.body(), &Body::Text(r#"{"ok":true}"#.to_string()));
    }

    #[test]
    fn error_response_uses_public_error_shape() {
        let response = error_response(&HttpError::bad_request("invalid request"));

        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response.body(),
            &Body::Text(r#"{"code":"bad_request","message":"invalid request"}"#.to_string())
        );
    }
}
