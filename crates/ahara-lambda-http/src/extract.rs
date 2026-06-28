use lambda_http::{Body, Request};
use serde::de::DeserializeOwned;

use crate::error::HttpError;

pub fn body_bytes(body: &Body) -> &[u8] {
    match body {
        Body::Empty => &[],
        Body::Text(value) => value.as_bytes(),
        Body::Binary(value) => value.as_slice(),
    }
}

pub fn json_body<T: DeserializeOwned>(request: &Request) -> Result<T, HttpError> {
    let body = body_bytes(request.body());
    if body.is_empty() {
        return Err(HttpError::bad_request("request body is required"));
    }

    serde_json::from_slice(body)
        .map_err(|error| HttpError::bad_request(format!("invalid JSON body: {error}")))
}

pub fn query_params<T: DeserializeOwned>(request: &Request) -> Result<T, HttpError> {
    serde_urlencoded::from_str(request.uri().query().unwrap_or_default())
        .map_err(|error| HttpError::bad_request(format!("invalid query string: {error}")))
}

#[cfg(test)]
mod tests {
    use lambda_http::Body;
    use serde::Deserialize;

    use super::{body_bytes, json_body, query_params};

    #[derive(Debug, Deserialize, PartialEq, Eq)]
    struct Payload {
        name: String,
    }

    #[derive(Debug, Deserialize, PartialEq, Eq)]
    struct Query {
        name: String,
        count: u16,
    }

    #[test]
    fn body_bytes_supports_text_binary_and_empty_bodies() {
        assert_eq!(body_bytes(&Body::Empty), b"");
        assert_eq!(body_bytes(&Body::Text("hello".to_string())), b"hello");
        assert_eq!(body_bytes(&Body::Binary(vec![1, 2, 3])), &[1, 2, 3]);
    }

    #[test]
    fn json_body_deserializes_request_body() {
        let request = lambda_http::http::Request::builder()
            .body(Body::Text(r#"{"name":"ahara"}"#.to_string()))
            .unwrap();

        assert_eq!(
            json_body::<Payload>(&request).unwrap(),
            Payload {
                name: "ahara".to_string()
            }
        );
    }

    #[test]
    fn query_params_deserializes_uri_query() {
        let request = lambda_http::http::Request::builder()
            .uri("/items?name=ahara&count=2")
            .body(Body::Empty)
            .unwrap();

        assert_eq!(
            query_params::<Query>(&request).unwrap(),
            Query {
                name: "ahara".to_string(),
                count: 2,
            }
        );
    }
}
