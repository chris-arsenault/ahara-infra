use lambda_http::http::header::{
    ACCESS_CONTROL_ALLOW_CREDENTIALS, ACCESS_CONTROL_ALLOW_HEADERS, ACCESS_CONTROL_ALLOW_METHODS,
    ACCESS_CONTROL_ALLOW_ORIGIN, ACCESS_CONTROL_EXPOSE_HEADERS, ACCESS_CONTROL_MAX_AGE,
};
use lambda_http::http::HeaderValue;
use lambda_http::{Body, Response};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CorsConfig {
    allow_origin: HeaderValue,
    allow_methods: HeaderValue,
    allow_headers: HeaderValue,
    expose_headers: Option<HeaderValue>,
    allow_credentials: Option<HeaderValue>,
    max_age_seconds: Option<HeaderValue>,
}

impl Default for CorsConfig {
    fn default() -> Self {
        Self {
            allow_origin: HeaderValue::from_static("*"),
            allow_methods: HeaderValue::from_static("GET,POST,PUT,PATCH,DELETE,HEAD,OPTIONS"),
            allow_headers: HeaderValue::from_static("*"),
            expose_headers: None,
            allow_credentials: None,
            max_age_seconds: None,
        }
    }
}

impl CorsConfig {
    pub fn allow_origin(mut self, value: HeaderValue) -> Self {
        self.allow_origin = value;
        self
    }

    pub fn allow_methods(mut self, value: HeaderValue) -> Self {
        self.allow_methods = value;
        self
    }

    pub fn allow_headers(mut self, value: HeaderValue) -> Self {
        self.allow_headers = value;
        self
    }

    pub fn expose_headers(mut self, value: HeaderValue) -> Self {
        self.expose_headers = Some(value);
        self
    }

    pub fn allow_credentials(mut self, allow: bool) -> Self {
        self.allow_credentials = allow.then(|| HeaderValue::from_static("true"));
        self
    }

    pub fn max_age_seconds(mut self, seconds: u64) -> Self {
        self.max_age_seconds = Some(
            HeaderValue::from_str(&seconds.to_string())
                .expect("u64 decimal string is a valid header value"),
        );
        self
    }

    pub fn apply(&self, response: &mut Response<Body>) {
        let headers = response.headers_mut();
        headers.insert(ACCESS_CONTROL_ALLOW_ORIGIN, self.allow_origin.clone());
        headers.insert(ACCESS_CONTROL_ALLOW_METHODS, self.allow_methods.clone());
        headers.insert(ACCESS_CONTROL_ALLOW_HEADERS, self.allow_headers.clone());

        if let Some(value) = &self.expose_headers {
            headers.insert(ACCESS_CONTROL_EXPOSE_HEADERS, value.clone());
        }
        if let Some(value) = &self.allow_credentials {
            headers.insert(ACCESS_CONTROL_ALLOW_CREDENTIALS, value.clone());
        }
        if let Some(value) = &self.max_age_seconds {
            headers.insert(ACCESS_CONTROL_MAX_AGE, value.clone());
        }
    }

    pub fn with_headers(&self, mut response: Response<Body>) -> Response<Body> {
        self.apply(&mut response);
        response
    }
}

pub fn default_cors(response: Response<Body>) -> Response<Body> {
    CorsConfig::default().with_headers(response)
}

#[cfg(test)]
mod tests {
    use lambda_http::http::StatusCode;
    use lambda_http::{Body, Response};

    use super::CorsConfig;

    #[test]
    fn default_cors_adds_actual_response_headers() {
        let response = CorsConfig::default().with_headers(
            Response::builder()
                .status(StatusCode::OK)
                .body(Body::Empty)
                .unwrap(),
        );

        assert_eq!(
            response
                .headers()
                .get("access-control-allow-origin")
                .unwrap(),
            "*"
        );
        assert_eq!(
            response
                .headers()
                .get("access-control-allow-methods")
                .unwrap(),
            "GET,POST,PUT,PATCH,DELETE,HEAD,OPTIONS"
        );
        assert_eq!(
            response
                .headers()
                .get("access-control-allow-headers")
                .unwrap(),
            "*"
        );
    }
}
