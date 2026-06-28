use std::str::FromStr;

use lambda_http::http::Method;
use lambda_http::Request;
use percent_encoding::percent_decode_str;

use crate::error::HttpError;

#[derive(Debug, Clone, Copy)]
pub struct Route<'a> {
    method: &'a Method,
    path: &'a str,
}

impl<'a> Route<'a> {
    pub fn new(method: &'a Method, path: &'a str) -> Self {
        Self { method, path }
    }

    pub fn from_request(request: &'a Request) -> Self {
        Self::new(request.method(), request.uri().path())
    }

    pub fn matches(
        &self,
        method: Method,
        pattern: impl AsRef<str>,
    ) -> Result<Option<PathParams>, HttpError> {
        if self.method != method {
            return Ok(None);
        }
        RoutePattern::new(pattern).matches(self.path)
    }

    pub fn is_match(&self, method: Method, pattern: impl AsRef<str>) -> Result<bool, HttpError> {
        self.matches(method, pattern)
            .map(|matched| matched.is_some())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoutePattern {
    pattern: String,
}

impl RoutePattern {
    pub fn new(pattern: impl AsRef<str>) -> Self {
        Self {
            pattern: pattern.as_ref().to_string(),
        }
    }

    pub fn matches(&self, path: &str) -> Result<Option<PathParams>, HttpError> {
        match_segments(split_segments(&self.pattern), split_segments(path))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PathParams {
    values: Vec<(String, String)>,
}

impl PathParams {
    fn new(values: Vec<(String, String)>) -> Self {
        Self { values }
    }

    pub fn empty() -> Self {
        Self { values: Vec::new() }
    }

    pub fn get(&self, name: &str) -> Option<&str> {
        self.values
            .iter()
            .find_map(|(key, value)| (key == name).then_some(value.as_str()))
    }

    pub fn require(&self, name: &str) -> Result<&str, HttpError> {
        self.get(name)
            .ok_or_else(|| HttpError::bad_request(format!("missing path parameter: {name}")))
    }

    pub fn parse<T>(&self, name: &str) -> Result<T, HttpError>
    where
        T: FromStr,
        T::Err: std::fmt::Display,
    {
        self.require(name)?.parse::<T>().map_err(|error| {
            HttpError::bad_request(format!("invalid path parameter {name}: {error}"))
        })
    }

    pub fn iter(&self) -> impl Iterator<Item = (&str, &str)> {
        self.values
            .iter()
            .map(|(key, value)| (key.as_str(), value.as_str()))
    }
}

fn match_segments(pattern: Vec<&str>, path: Vec<&str>) -> Result<Option<PathParams>, HttpError> {
    let mut values = Vec::new();
    let mut pattern_index = 0;
    let mut path_index = 0;

    while let Some(pattern_segment) = pattern.get(pattern_index) {
        if let Some(wildcard_name) = wildcard_name(pattern_segment)? {
            let rest = path[path_index..].join("/");
            values.push((wildcard_name.to_string(), decode_segment(&rest)));
            return Ok(Some(PathParams::new(values)));
        }

        let Some(path_segment) = path.get(path_index) else {
            return Ok(None);
        };

        if let Some(param_name) = param_name(pattern_segment)? {
            values.push((param_name.to_string(), decode_segment(path_segment)));
        } else if *pattern_segment != *path_segment {
            return Ok(None);
        }

        pattern_index += 1;
        path_index += 1;
    }

    if path_index == path.len() {
        Ok(Some(PathParams::new(values)))
    } else {
        Ok(None)
    }
}

fn split_segments(path: &str) -> Vec<&str> {
    let trimmed = path.trim_matches('/');
    if trimmed.is_empty() {
        Vec::new()
    } else {
        trimmed.split('/').collect()
    }
}

fn param_name(segment: &str) -> Result<Option<&str>, HttpError> {
    if !segment.starts_with('{') && !segment.ends_with('}') {
        return Ok(None);
    }
    if segment.starts_with('{') && segment.ends_with('}') {
        let name = &segment[1..segment.len() - 1];
        if name.is_empty() || name.starts_with('*') {
            return Err(HttpError::internal(format!(
                "invalid route parameter segment: {segment}"
            )));
        }
        return Ok(Some(name));
    }
    Err(HttpError::internal(format!(
        "invalid route parameter segment: {segment}"
    )))
}

fn wildcard_name(segment: &str) -> Result<Option<&str>, HttpError> {
    if segment == "*" {
        return Ok(Some("wildcard"));
    }
    if segment.starts_with("{*") && segment.ends_with('}') {
        let name = &segment[2..segment.len() - 1];
        if name.is_empty() {
            return Err(HttpError::internal(format!(
                "invalid route wildcard segment: {segment}"
            )));
        }
        return Ok(Some(name));
    }
    Ok(None)
}

fn decode_segment(value: &str) -> String {
    percent_decode_str(value).decode_utf8_lossy().into_owned()
}

#[cfg(test)]
mod tests {
    use lambda_http::http::Method;
    use lambda_http::Body;

    use super::{PathParams, Route, RoutePattern};

    #[test]
    fn route_matches_static_paths_and_methods() {
        let request = lambda_http::http::Request::builder()
            .method(Method::GET)
            .uri("/health")
            .body(Body::Empty)
            .unwrap();
        let route = Route::from_request(&request);

        assert_eq!(
            route.matches(Method::GET, "/health").unwrap(),
            Some(PathParams::empty())
        );
        assert_eq!(route.matches(Method::POST, "/health").unwrap(), None);
        assert_eq!(route.matches(Method::GET, "/other").unwrap(), None);
    }

    #[test]
    fn route_extracts_named_path_parameters() {
        let request = lambda_http::http::Request::builder()
            .method(Method::DELETE)
            .uri("/audiences/a-1/members/p-2")
            .body(Body::Empty)
            .unwrap();
        let route = Route::from_request(&request);
        let params = route
            .matches(
                Method::DELETE,
                "/audiences/{audience_id}/members/{principal_id}",
            )
            .unwrap()
            .unwrap();

        assert_eq!(params.get("audience_id"), Some("a-1"));
        assert_eq!(params.get("principal_id"), Some("p-2"));
    }

    #[test]
    fn route_percent_decodes_path_parameters() {
        let params = RoutePattern::new("/files/{name}")
            .matches("/files/hello%20world.txt")
            .unwrap()
            .unwrap();

        assert_eq!(params.get("name"), Some("hello world.txt"));
    }

    #[test]
    fn route_supports_terminal_wildcards() {
        let params = RoutePattern::new("/assets/{*key}")
            .matches("/assets/a/b/c.txt")
            .unwrap()
            .unwrap();

        assert_eq!(params.get("key"), Some("a/b/c.txt"));
    }
}
