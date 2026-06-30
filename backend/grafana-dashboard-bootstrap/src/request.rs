use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct BootstrapRequest {
    pub action: String,
}

#[derive(Debug, Serialize)]
pub struct BootstrapResponse {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub service_account_id: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub token_parameter: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl BootstrapResponse {
    pub fn success(service_account_id: i64, token_parameter: String) -> Self {
        Self {
            success: true,
            service_account_id: Some(service_account_id),
            token_parameter: Some(token_parameter),
            error: None,
        }
    }

    pub fn failure(error: String) -> Self {
        Self {
            success: false,
            service_account_id: None,
            token_parameter: None,
            error: Some(error),
        }
    }
}
