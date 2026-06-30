use std::collections::BTreeSet;

use lambda_runtime::Error;
use serde_json::Value;

use crate::request::{DashboardSpec, DeployRequest, PreparedDashboard};

const MANAGED_TAG: &str = "ahara:managed";
const BUILTIN_DATASOURCES: &[&str] = &["-- Grafana --", "grafana"];

pub fn validate_request(request: &DeployRequest) -> Result<(), Error> {
    validate_name("project", &request.project)?;
    validate_name("folder_uid", &request.folder_uid)?;
    if request.folder_title.trim().is_empty() {
        return Err(error("folder_title is required"));
    }
    if request.dashboards.is_empty() {
        return Err(error("at least one dashboard is required"));
    }
    Ok(())
}

pub fn prepare_dashboard(
    spec: &DashboardSpec,
    project: &str,
    repo_tag: &str,
    allowed_datasources: &BTreeSet<String>,
) -> Result<PreparedDashboard, Error> {
    let uid = dashboard_string(&spec.dashboard, "uid", &spec.path)?;
    validate_uid(&uid, &spec.path)?;
    let title = dashboard_string(&spec.dashboard, "title", &spec.path)?;
    let mut dashboard = spec.dashboard.clone();
    strip_instance_fields(&mut dashboard);
    add_managed_tags(&mut dashboard, project, repo_tag)?;
    validate_datasources(&dashboard, allowed_datasources, &spec.path)?;
    Ok(PreparedDashboard {
        path: spec.path.clone(),
        uid,
        title,
        dashboard,
    })
}

fn dashboard_string(dashboard: &Value, field: &str, path: &str) -> Result<String, Error> {
    dashboard
        .get(field)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .ok_or_else(|| error(format!("{path}: dashboard.{field} is required")))
}

fn strip_instance_fields(dashboard: &mut Value) {
    if let Some(object) = dashboard.as_object_mut() {
        object.remove("id");
        object.remove("version");
    }
}

fn add_managed_tags(dashboard: &mut Value, project: &str, repo_tag: &str) -> Result<(), Error> {
    let object = dashboard
        .as_object_mut()
        .ok_or_else(|| error("dashboard JSON must be an object"))?;
    let tags = object
        .entry("tags")
        .or_insert_with(|| Value::Array(Vec::new()))
        .as_array_mut()
        .ok_or_else(|| error("dashboard.tags must be an array when present"))?;

    push_tag(tags, MANAGED_TAG);
    push_tag(tags, repo_tag);
    push_tag(tags, &format!("project:{project}"));
    Ok(())
}

fn push_tag(tags: &mut Vec<Value>, tag: &str) {
    let exists = tags.iter().any(|value| value.as_str() == Some(tag));
    if !exists {
        tags.push(Value::String(tag.to_string()));
    }
}

fn validate_datasources(
    dashboard: &Value,
    allowed_datasources: &BTreeSet<String>,
    path: &str,
) -> Result<(), Error> {
    if allowed_datasources.is_empty() {
        return Ok(());
    }
    let mut used = BTreeSet::new();
    collect_datasource_uids(dashboard, &mut used);
    let unknown = used
        .into_iter()
        .filter(|uid| !allowed_datasources.contains(uid))
        .collect::<Vec<_>>();
    if unknown.is_empty() {
        Ok(())
    } else {
        Err(error(format!(
            "{path}: dashboard references unapproved datasource uid(s): {}",
            unknown.join(", ")
        )))
    }
}

fn collect_datasource_uids(value: &Value, used: &mut BTreeSet<String>) {
    match value {
        Value::Array(values) => {
            for item in values {
                collect_datasource_uids(item, used);
            }
        }
        Value::Object(object) => {
            if let Some(uid) = datasource_uid(value) {
                used.insert(uid);
            }
            for child in object.values() {
                collect_datasource_uids(child, used);
            }
        }
        _ => {}
    }
}

fn datasource_uid(value: &Value) -> Option<String> {
    let datasource = value.get("datasource")?.as_object()?;
    let uid = datasource.get("uid")?.as_str()?.trim();
    if uid.is_empty() || uid.starts_with('$') || BUILTIN_DATASOURCES.contains(&uid) {
        None
    } else {
        Some(uid.to_string())
    }
}

fn validate_name(field: &str, value: &str) -> Result<(), Error> {
    let value = value.trim();
    if value.is_empty() {
        return Err(error(format!("{field} is required")));
    }
    if !value
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'))
    {
        return Err(error(format!(
            "{field} may only contain ASCII letters, numbers, dot, dash, and underscore"
        )));
    }
    Ok(())
}

fn validate_uid(uid: &str, path: &str) -> Result<(), Error> {
    if !uid
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
    {
        return Err(error(format!(
            "{path}: dashboard.uid may only contain ASCII letters, numbers, dash, and underscore"
        )));
    }
    Ok(())
}

fn error(message: impl Into<String>) -> Error {
    std::io::Error::other(message.into()).into()
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn prepare_dashboard_strips_instance_fields_and_adds_tags() {
        let spec = DashboardSpec {
            path: "observability/dashboards/app.json".into(),
            dashboard: json!({
                "id": 15,
                "version": 7,
                "uid": "app-overview",
                "title": "App Overview",
                "tags": ["existing"],
                "panels": []
            }),
        };

        let prepared = prepare_dashboard(&spec, "app", "ahara:repo:app", &BTreeSet::new()).unwrap();

        assert!(prepared.dashboard.get("id").is_none());
        assert!(prepared.dashboard.get("version").is_none());
        assert_eq!(prepared.uid, "app-overview");
        assert_eq!(prepared.title, "App Overview");
        assert_eq!(
            prepared.dashboard["tags"],
            json!(["existing", "ahara:managed", "ahara:repo:app", "project:app"])
        );
    }

    #[test]
    fn prepare_dashboard_rejects_unknown_datasource_uids() {
        let spec = DashboardSpec {
            path: "observability/dashboards/app.json".into(),
            dashboard: json!({
                "uid": "app-overview",
                "title": "App Overview",
                "panels": [{ "datasource": { "uid": "unknown" } }]
            }),
        };
        let allowed = BTreeSet::from(["loki".to_string()]);

        let error = prepare_dashboard(&spec, "app", "ahara:repo:app", &allowed).unwrap_err();

        assert!(error
            .to_string()
            .contains("unapproved datasource uid(s): unknown"));
    }
}
