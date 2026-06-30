use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Deserialize)]
pub struct DeployRequest {
    pub project: String,
    pub folder_uid: String,
    pub folder_title: String,
    #[serde(default)]
    pub prune: bool,
    #[serde(default)]
    pub dashboards: Vec<DashboardSpec>,
}

#[derive(Debug, Deserialize)]
pub struct DashboardSpec {
    pub path: String,
    pub dashboard: Value,
}

#[derive(Debug, Serialize)]
pub struct DeployResponse {
    pub project: String,
    pub folder_uid: String,
    pub folder_title: String,
    pub upserted: Vec<DashboardResult>,
    pub pruned: Vec<PrunedDashboard>,
}

#[derive(Debug, Serialize)]
pub struct DashboardResult {
    pub path: String,
    pub uid: String,
    pub title: String,
    pub url: String,
    pub action: DashboardAction,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DashboardAction {
    Created,
    Updated,
}

#[derive(Debug, Serialize)]
pub struct PrunedDashboard {
    pub uid: String,
    pub title: String,
}

#[derive(Debug)]
pub struct PreparedDashboard {
    pub path: String,
    pub uid: String,
    pub title: String,
    pub dashboard: Value,
}
