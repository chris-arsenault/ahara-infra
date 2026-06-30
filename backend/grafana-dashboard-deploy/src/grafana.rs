use lambda_runtime::Error;
use reqwest::{Client, Method, StatusCode};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::request::{DashboardAction, DashboardResult, PreparedDashboard, PrunedDashboard};

#[derive(Clone)]
pub struct GrafanaClient {
    http: Client,
    base_url: String,
    token: String,
}

impl GrafanaClient {
    pub fn new(http: Client, base_url: String, token: String) -> Self {
        Self {
            http,
            base_url: base_url.trim_end_matches('/').to_string(),
            token,
        }
    }

    pub async fn ensure_folder(&self, uid: &str, title: &str) -> Result<(), Error> {
        match self.get_folder(uid).await? {
            Some(folder) if folder.title == title => Ok(()),
            Some(_) => {
                self.request_json(
                    Method::PUT,
                    &format!("/api/folders/{uid}"),
                    Some(json!({ "title": title })),
                )
                .await?;
                Ok(())
            }
            None => {
                self.request_json(
                    Method::POST,
                    "/api/folders",
                    Some(json!({ "uid": uid, "title": title })),
                )
                .await?;
                Ok(())
            }
        }
    }

    pub async fn upsert_dashboard(
        &self,
        dashboard: &PreparedDashboard,
        folder_uid: &str,
        message: &str,
    ) -> Result<DashboardResult, Error> {
        let exists = self.dashboard_exists(&dashboard.uid).await?;
        self.request_json(
            Method::POST,
            "/api/dashboards/db",
            Some(dashboard_body(dashboard, folder_uid, message)),
        )
        .await?;

        let action = if exists {
            DashboardAction::Updated
        } else {
            DashboardAction::Created
        };
        Ok(DashboardResult {
            path: dashboard.path.clone(),
            uid: dashboard.uid.clone(),
            title: dashboard.title.clone(),
            url: format!("/d/{}", dashboard.uid),
            action,
        })
    }

    pub async fn prune_dashboards(
        &self,
        folder_uid: &str,
        repo_tag: &str,
        desired_uids: &[String],
    ) -> Result<Vec<PrunedDashboard>, Error> {
        let desired = desired_uids
            .iter()
            .collect::<std::collections::BTreeSet<_>>();
        let mut pruned = Vec::new();

        for dashboard in self.managed_dashboards(folder_uid, repo_tag).await? {
            if desired.contains(&dashboard.uid) {
                continue;
            }
            self.delete_dashboard(&dashboard.uid).await?;
            pruned.push(PrunedDashboard {
                uid: dashboard.uid,
                title: dashboard.title,
            });
        }

        Ok(pruned)
    }

    async fn get_folder(&self, uid: &str) -> Result<Option<Folder>, Error> {
        self.get_optional_json(&format!("/api/folders/{uid}")).await
    }

    async fn dashboard_exists(&self, uid: &str) -> Result<bool, Error> {
        self.get_optional_json::<Value>(&format!("/api/dashboards/uid/{uid}"))
            .await
            .map(|dashboard| dashboard.is_some())
    }

    async fn managed_dashboards(
        &self,
        folder_uid: &str,
        repo_tag: &str,
    ) -> Result<Vec<SearchDashboard>, Error> {
        let mut request = self
            .http
            .get(self.url("/api/search"))
            .bearer_auth(&self.token)
            .query(&[
                ("type", "dash-db"),
                ("folderUIDs", folder_uid),
                ("tag", repo_tag),
                ("limit", "5000"),
            ]);
        request = request.query(&[("deleted", "false")]);
        let response = request.send().await.map_err(to_error)?;
        let dashboards: Vec<SearchDashboard> =
            decode_response(response, "GET", "/api/search").await?;
        Ok(dashboards
            .into_iter()
            .filter(|dashboard| dashboard.matches(folder_uid, repo_tag))
            .collect())
    }

    async fn delete_dashboard(&self, uid: &str) -> Result<(), Error> {
        self.request_json(Method::DELETE, &format!("/api/dashboards/uid/{uid}"), None)
            .await?;
        Ok(())
    }

    async fn get_optional_json<T>(&self, path: &str) -> Result<Option<T>, Error>
    where
        T: for<'de> Deserialize<'de>,
    {
        let response = self
            .http
            .get(self.url(path))
            .bearer_auth(&self.token)
            .send()
            .await
            .map_err(to_error)?;
        if response.status() == StatusCode::NOT_FOUND {
            return Ok(None);
        }
        decode_response(response, "GET", path).await.map(Some)
    }

    async fn request_json(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<Value, Error> {
        let mut request = self
            .http
            .request(method.clone(), self.url(path))
            .bearer_auth(&self.token);
        if let Some(body) = body {
            request = request.json(&body);
        }
        let response = request.send().await.map_err(to_error)?;
        decode_response(response, method.as_str(), path).await
    }

    fn url(&self, path: &str) -> String {
        format!("{}/{}", self.base_url, path.trim_start_matches('/'))
    }
}

fn dashboard_body(dashboard: &PreparedDashboard, folder_uid: &str, message: &str) -> Value {
    json!({
        "dashboard": dashboard.dashboard,
        "folderUid": folder_uid,
        "message": message,
        "overwrite": true
    })
}

async fn decode_response<T>(
    response: reqwest::Response,
    method: &str,
    path: &str,
) -> Result<T, Error>
where
    T: for<'de> Deserialize<'de>,
{
    let status = response.status();
    let text = response.text().await.map_err(to_error)?;
    if !status.is_success() {
        return Err(error(format!(
            "Grafana {method} {path} failed with {status}: {text}"
        )));
    }
    if text.trim().is_empty() {
        serde_json::from_value(Value::Null).map_err(to_error)
    } else {
        serde_json::from_str(&text).map_err(to_error)
    }
}

fn to_error(error: impl std::error::Error + Send + Sync + 'static) -> Error {
    Box::new(error)
}

fn error(message: impl Into<String>) -> Error {
    std::io::Error::other(message.into()).into()
}

#[derive(Deserialize)]
struct Folder {
    title: String,
}

#[derive(Deserialize)]
struct SearchDashboard {
    uid: String,
    title: String,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default, rename = "folderUid")]
    folder_uid: Option<String>,
}

impl SearchDashboard {
    fn matches(&self, folder_uid: &str, repo_tag: &str) -> bool {
        self.folder_uid.as_deref() == Some(folder_uid)
            && self.tags.iter().any(|tag| tag == repo_tag)
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn dashboard_body_uses_classic_grafana_api_shape() {
        let dashboard = PreparedDashboard {
            path: "dashboards/example.json".into(),
            uid: "example".into(),
            title: "Example".into(),
            dashboard: json!({ "uid": "example", "title": "Example" }),
        };

        assert_eq!(
            dashboard_body(&dashboard, "folder", "deploy"),
            json!({
                "dashboard": { "uid": "example", "title": "Example" },
                "folderUid": "folder",
                "message": "deploy",
                "overwrite": true
            })
        );
    }

    #[test]
    fn search_dashboard_matches_managed_folder_and_repo_tag() {
        let dashboard = SearchDashboard {
            uid: "env".into(),
            title: "Environment".into(),
            folder_uid: Some("house-sensors".into()),
            tags: vec!["ahara:managed".into(), "ahara:repo:house-sensors".into()],
        };

        assert!(dashboard.matches("house-sensors", "ahara:repo:house-sensors"));
        assert!(!dashboard.matches("other", "ahara:repo:house-sensors"));
        assert!(!dashboard.matches("house-sensors", "ahara:repo:other"));
    }
}
