use aws_config::BehaviorVersion;
use aws_sdk_s3::Client;
use lambda_http::Error;
use serde::Deserialize;
use std::collections::HashMap;
use tokio::sync::OnceCell;

#[derive(Deserialize)]
pub(crate) struct ManifestDocument {
    pub(crate) routes: HashMap<String, ManifestRoute>,
}

#[derive(Deserialize)]
pub(crate) struct ManifestRoute {
    pub(crate) title: String,
    pub(crate) description: String,
    #[serde(default)]
    pub(crate) image: String,
    #[serde(default = "default_og_type")]
    pub(crate) og_type: String,
}

fn default_og_type() -> String {
    "article".into()
}

pub(crate) struct ManifestLocation {
    pub(crate) bucket: String,
    pub(crate) key: String,
}

static MANIFEST: OnceCell<ManifestDocument> = OnceCell::const_new();

pub(crate) async fn load(location: &ManifestLocation) -> Result<&'static ManifestDocument, Error> {
    MANIFEST
        .get_or_try_init(|| async {
            let config = aws_config::load_defaults(BehaviorVersion::latest()).await;
            let response = Client::new(&config)
                .get_object()
                .bucket(&location.bucket)
                .key(&location.key)
                .send()
                .await?;
            let bytes = response.body.collect().await?.into_bytes();
            Ok(serde_json::from_slice(&bytes)?)
        })
        .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_ignores_export_fields_the_og_server_does_not_need() {
        let json = r#"{
          "routes": {
            "/world/entry/name": {
              "title": "Name · World",
              "description": "Entry summary",
              "world_id": "world",
              "entry_id": "name"
            }
          }
        }"#;
        let manifest: ManifestDocument = serde_json::from_str(json).expect("valid manifest");
        let route = manifest.routes.get("/world/entry/name").expect("route");
        assert_eq!(route.title, "Name · World");
        assert_eq!(route.og_type, "article");
    }
}
