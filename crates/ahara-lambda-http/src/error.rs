use std::borrow::Cow;
use std::error::Error;
use std::fmt;

use lambda_http::http::StatusCode;

/// Public error contract used by JSON error response helpers.
///
/// Application errors should keep private details in their own error type and
/// expose only safe status/code/message values through this trait or by
/// constructing [`HttpError`] values.
pub trait PublicHttpError {
    fn status_code(&self) -> StatusCode;
    fn code(&self) -> Cow<'_, str>;
    fn message(&self) -> Cow<'_, str>;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpError {
    status_code: StatusCode,
    code: Cow<'static, str>,
    message: Cow<'static, str>,
}

impl HttpError {
    pub fn new(
        status_code: StatusCode,
        code: impl Into<Cow<'static, str>>,
        message: impl Into<Cow<'static, str>>,
    ) -> Self {
        Self {
            status_code,
            code: code.into(),
            message: message.into(),
        }
    }

    pub fn bad_request(message: impl Into<Cow<'static, str>>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, "bad_request", message)
    }

    pub fn not_found() -> Self {
        Self::new(StatusCode::NOT_FOUND, "not_found", "not found")
    }

    pub fn method_not_allowed() -> Self {
        Self::new(
            StatusCode::METHOD_NOT_ALLOWED,
            "method_not_allowed",
            "method not allowed",
        )
    }

    pub fn internal(message: impl Into<Cow<'static, str>>) -> Self {
        Self::new(StatusCode::INTERNAL_SERVER_ERROR, "internal_error", message)
    }
}

impl PublicHttpError for HttpError {
    fn status_code(&self) -> StatusCode {
        self.status_code
    }

    fn code(&self) -> Cow<'_, str> {
        Cow::Borrowed(self.code.as_ref())
    }

    fn message(&self) -> Cow<'_, str> {
        Cow::Borrowed(self.message.as_ref())
    }
}

impl fmt::Display for HttpError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "{} {}: {}",
            self.status_code.as_u16(),
            self.code,
            self.message
        )
    }
}

impl Error for HttpError {}
