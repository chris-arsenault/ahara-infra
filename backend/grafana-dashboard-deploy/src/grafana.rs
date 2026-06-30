use std::collections::HashMap;

use lambda_runtime::Error;
use reqwest::{Client, Method, StatusCode};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::request::{DashboardAction, DashboardResult, PreparedDashboard, PrunedDashboard};

const FOLDER_ANNOTATION: &str = "grafana.app/folder";
const MESSAGE_ANNOTATION: &str = "grafana.app/message";

#[derive(Clone)]
pub struct GrafanaClient {
    http: Client,
    base_url: String,
    token: String,
    namespace: String,
}

impl GrafanaClient {
    pub fn new(http: Client, base_url: String, token: String, namespace: String) -> Self {
        Self {
            http,
            base_url: base_url.trim_end_matches('/').to_string(),
            token,
            namespace,
        }
    }

    pub async fn ensure_folder(&self, uid: &str, title: &str) -> Result<(), Error> {
        match self.get_folder(uid).await? {
            Some(folder) if folder.title() == title => Ok(()),
            Some(_) => {
                self.put_json(&folder_path(&self.namespace, uid), folder_body(uid, title))
                    .await?;
                Ok(())
            }
            None => {
                self.post_json(&folders_path(&self.namespace), folder_body(uid, title))
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
        let exists = self.get_dashboard(&dashboard.uid).await?.is_some();
        let body = dashboard_body(dashboard, folder_uid, message);
        let path = dashboard_path(&self.namespace, &dashboard.uid);
        let action = if exists {
            self.put_json(&path, body).await?;
            DashboardAction::Updated
        } else {
            self.post_json(&dashboards_path(&self.namespace), body)
                .await?;
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
        let dashboards = self.managed_dashboards(folder_uid, repo_tag).await?;
        let mut pruned = Vec::new();

        for dashboard in dashboards {
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

    async fn get_folder(&self, uid: &str) -> Result<Option<FolderResource>, Error> {
        self.get_optional_json(&folder_path(&self.namespace, uid))
            .await
    }

    async fn get_dashboard(&self, uid: &str) -> Result<Option<Value>, Error> {
        self.get_optional_json(&dashboard_path(&self.namespace, uid))
            .await
    }

    async fn managed_dashboards(
        &self,
        folder_uid: &str,
        repo_tag: &str,
    ) -> Result<Vec<ManagedDashboard>, Error> {
        let mut dashboards = Vec::new();
        let mut continue_token = None;

        loop {
            let page = self.list_dashboard_page(continue_token.as_deref()).await?;
            for item in page.items {
                if item.matches(folder_uid, repo_tag) {
                    let title = item.spec_title();
                    dashboards.push(ManagedDashboard {
                        uid: item.metadata.name,
                        title,
                    });
                }
            }
            continue_token = page.metadata.and_then(|metadata| metadata.continue_token);
            if continue_token.is_none() {
                break;
            }
        }

        Ok(dashboards)
    }

    async fn list_dashboard_page(
        &self,
        continue_token: Option<&str>,
    ) -> Result<ResourceList, Error> {
        let url = self.url(&dashboards_path(&self.namespace));
        let mut request = self
            .http
            .get(url)
            .bearer_auth(&self.token)
            .query(&[("limit", "500")]);
        if let Some(token) = continue_token {
            request = request.query(&[("continue", token)]);
        }
        let response = request.send().await.map_err(to_error)?;
        decode_response(response).await
    }

    async fn delete_dashboard(&self, uid: &str) -> Result<(), Error> {
        self.request_json(Method::DELETE, &dashboard_path(&self.namespace, uid), None)
            .await?;
        Ok(())
    }

    async fn post_json(&self, path: &str, body: Value) -> Result<Value, Error> {
        self.request_json(Method::POST, path, Some(body)).await
    }

    async fn put_json(&self, path: &str, body: Value) -> Result<Value, Error> {
        self.request_json(Method::PUT, path, Some(body)).await
    }

    async fn get_optional_json<T>(&self, path: &str) -> Result<Option<T>, Error>
    where
        T: for<'de> Deserialize<'de>,
    {
        let url = self.url(path);
        let response = self
            .http
            .get(url)
            .bearer_auth(&self.token)
            .send()
            .await
            .map_err(to_error)?;
        if response.status() == StatusCode::NOT_FOUND {
            return Ok(None);
        }
        decode_response(response).await.map(Some)
    }

    async fn request_json(
        &self,
        method: Method,
        path: &str,
        body: Option<Value>,
    ) -> Result<Value, Error> {
        let mut request = self
            .http
            .request(method, self.url(path))
            .bearer_auth(&self.token);
        if let Some(body) = body {
            request = request.json(&body);
        }
        let response = request.send().await.map_err(to_error)?;
        decode_response(response).await
    }

    fn url(&self, path: &str) -> String {
        format!("{}/{}", self.base_url, path.trim_start_matches('/'))
    }
}

fn folders_path(namespace: &str) -> String {
    format!("/apis/folder.grafana.app/v1/namespaces/{namespace}/folders")
}

fn folder_path(namespace: &str, uid: &str) -> String {
    format!("{}/{}", folders_path(namespace), uid)
}

fn dashboards_path(namespace: &str) -> String {
    format!("/apis/dashboard.grafana.app/v1/namespaces/{namespace}/dashboards")
}

fn dashboard_path(namespace: &str, uid: &str) -> String {
    format!("{}/{}", dashboards_path(namespace), uid)
}

fn folder_body(uid: &str, title: &str) -> Value {
    json!({
        "apiVersion": "folder.grafana.app/v1",
        "kind": "Folder",
        "metadata": { "name": uid },
        "spec": { "title": title }
    })
}

fn dashboard_body(dashboard: &PreparedDashboard, folder_uid: &str, message: &str) -> Value {
    json!({
        "apiVersion": "dashboard.grafana.app/v1",
        "kind": "Dashboard",
        "metadata": {
            "name": dashboard.uid,
            "annotations": {
                FOLDER_ANNOTATION: folder_uid,
                MESSAGE_ANNOTATION: message
            }
        },
        "spec": dashboard.dashboard
    })
}

async fn decode_response<T>(response: reqwest::Response) -> Result<T, Error>
where
    T: for<'de> Deserialize<'de>,
{
    let status = response.status();
    let text = response.text().await.map_err(to_error)?;
    if !status.is_success() {
        return Err(error(format!("Grafana API {status}: {text}")));
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
struct FolderResource {
    spec: FolderSpec,
}

impl FolderResource {
    fn title(&self) -> &str {
        &self.spec.title
    }
}

#[derive(Deserialize)]
struct FolderSpec {
    title: String,
}

#[derive(Deserialize)]
struct ResourceList {
    metadata: Option<ListMetadata>,
    #[serde(default)]
    items: Vec<DashboardResource>,
}

#[derive(Deserialize)]
struct ListMetadata {
    #[serde(rename = "continue")]
    continue_token: Option<String>,
}

#[derive(Deserialize)]
struct DashboardResource {
    metadata: ResourceMetadata,
    spec: Value,
}

impl DashboardResource {
    fn matches(&self, folder_uid: &str, repo_tag: &str) -> bool {
        self.in_folder(folder_uid) && self.has_tag(repo_tag)
    }

    fn in_folder(&self, folder_uid: &str) -> bool {
        self.metadata
            .annotations
            .as_ref()
            .and_then(|annotations| annotations.get(FOLDER_ANNOTATION))
            .map(|value| value == folder_uid)
            .unwrap_or_default()
    }

    fn has_tag(&self, tag: &str) -> bool {
        self.spec
            .get("tags")
            .and_then(Value::as_array)
            .map(|tags| tags.iter().any(|value| value.as_str() == Some(tag)))
            .unwrap_or_default()
    }

    fn spec_title(&self) -> String {
        self.spec
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string()
    }
}

#[derive(Deserialize)]
struct ResourceMetadata {
    name: String,
    annotations: Option<HashMap<String, String>>,
}

struct ManagedDashboard {
    uid: String,
    title: String,
}
