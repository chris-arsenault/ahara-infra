/// Platform-wide CORS preflight handler.
/// Responds to all OPTIONS requests with permissive CORS headers.
/// Deployed as a single Lambda behind ALB priority 1.
use lambda_http::{Body, Error, Request, Response, run, service_fn};

const ALLOWED_METHODS: &str = "GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD";
const DEFAULT_ALLOWED_HEADERS: &str = "Authorization, Content-Type, If-Match, If-None-Match";
const MAX_AGE_SECONDS: &str = "86400";

fn request_header<'a>(req: &'a Request, name: &str) -> Option<&'a str> {
    req.headers()
        .get(name)
        .and_then(|value| value.to_str().ok())
}

fn origin_host(origin: &str) -> Option<&str> {
    let origin = origin
        .strip_prefix("https://")
        .or_else(|| origin.strip_prefix("http://"))?;
    Some(origin.split(':').next().unwrap_or_default())
}

fn is_allowed_origin(origin: &str) -> bool {
    let origin = origin.to_ascii_lowercase();
    let Some(host) = origin_host(&origin) else {
        return false;
    };

    matches!(host, "localhost" | "127.0.0.1" | "ahara.io" | "tsonu.com")
        || host.ends_with(".ahara.io")
        || host.ends_with(".tsonu.com")
}

fn allow_origin(req: &Request) -> String {
    request_header(req, "origin")
        .filter(|origin| is_allowed_origin(origin))
        .unwrap_or("*")
        .to_string()
}

fn allow_headers(req: &Request) -> &str {
    request_header(req, "access-control-request-headers").unwrap_or(DEFAULT_ALLOWED_HEADERS)
}

async fn handler(req: Request) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(204)
        .header("Access-Control-Allow-Origin", allow_origin(&req))
        .header("Access-Control-Allow-Methods", ALLOWED_METHODS)
        .header("Access-Control-Allow-Headers", allow_headers(&req))
        .header("Access-Control-Max-Age", MAX_AGE_SECONDS)
        .header(
            "Vary",
            "Origin, Access-Control-Request-Method, Access-Control-Request-Headers",
        )
        .body(Body::Empty)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(headers: &[(&str, &str)]) -> Request {
        let mut builder = lambda_http::http::Request::builder();
        for (name, value) in headers {
            builder = builder.header(*name, *value);
        }
        builder.body(Body::Empty).unwrap()
    }

    #[test]
    fn allows_tsonu_origins() {
        assert_eq!(
            allow_origin(&request(&[("origin", "https://music.tsonu.com")])),
            "https://music.tsonu.com"
        );
    }

    #[test]
    fn keeps_unknown_origins_permissive_without_reflecting_them() {
        assert_eq!(
            allow_origin(&request(&[("origin", "https://example.com")])),
            "*"
        );
    }

    #[test]
    fn reflects_requested_headers() {
        assert_eq!(
            allow_headers(&request(&[(
                "access-control-request-headers",
                "authorization,content-type,if-none-match",
            )])),
            "authorization,content-type,if-none-match"
        );
    }

    #[test]
    fn falls_back_to_conditional_request_headers() {
        assert_eq!(
            allow_headers(&request(&[])),
            "Authorization, Content-Type, If-Match, If-None-Match"
        );
    }
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .json()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("info".parse().unwrap()),
        )
        .without_time()
        .init();

    run(service_fn(handler)).await
}
