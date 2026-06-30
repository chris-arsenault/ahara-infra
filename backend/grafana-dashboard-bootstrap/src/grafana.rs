use lambda_runtime::Error;
use reqwest::{Client, Method, Response, StatusCode};
use serde::{Deserialize, Serialize};
use serde_json::json;
use tokio::time::{sleep, Duration};
use tracing::info;

#[derive(Clone)]
pub struct GrafanaAdminClient {
    http: Client,
    base_url: String,
    admin_user: String,
    admin_password: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ServiceAccount {
    pub id: i64,
    pub name: String,
    pub role: String,
    #[serde(default, rename = "isDisabled")]
    pub is_disabled: bool,
}

#[derive(Debug, Deserialize)]
struct ServiceAccountSearch {
    #[serde(default, rename = "serviceAccounts")]
    service_accounts: Vec<ServiceAccount>,
}

#[derive(Debug, Deserialize)]
struct ServiceAccountToken {
    id: i64,
    name: String,
}

#[derive(Debug, Deserialize)]
struct CreatedToken {
    key: String,
}

impl GrafanaAdminClient {
    pub fn new(
        http: Client,
        grafana_url: String,
        admin_user: String,
        admin_password: String,
    ) -> Self {
        Self {
            http,
            base_url: grafana_url.trim_end_matches('/').to_string(),
            admin_user,
            admin_password,
        }
    }

    pub async fn wait_for_health(&self) -> Result<(), Error> {
        for attempt in 1..=40 {
            if self.is_healthy().await {
                info!(attempt, "Grafana is healthy");
                return Ok(());
            }
            if attempt < 40 {
                info!(attempt, "Waiting for Grafana health");
                sleep(Duration::from_secs(15)).await;
            }
        }
        Err(std::io::Error::other("Grafana did not become healthy within 10 minutes").into())
    }

    pub async fn ensure_service_account(
        &self,
        name: &str,
        role: &str,
    ) -> Result<ServiceAccount, Error> {
        match self.find_service_account(name).await? {
            Some(account) if account.role == role && !account.is_disabled => Ok(account),
            Some(account) => self.update_service_account(&account, role).await,
            None => self.create_service_account(name, role).await,
        }
    }

    pub async fn rotate_named_token(
        &self,
        account_id: i64,
        token_name: &str,
    ) -> Result<String, Error> {
        for token in self.service_account_tokens(account_id).await? {
            if token.name == token_name {
                self.delete_service_account_token(account_id, token.id)
                    .await?;
            }
        }
        self.create_service_account_token(account_id, token_name)
            .await
    }

    async fn is_healthy(&self) -> bool {
        self.http
            .get(self.url("/api/health"))
            .send()
            .await
            .map(|response| response.status().is_success())
            .unwrap_or(false)
    }

    async fn find_service_account(&self, name: &str) -> Result<Option<ServiceAccount>, Error> {
        let response = self
            .request(Method::GET, "/api/serviceaccounts/search")
            .query(&[("query", name), ("perpage", "100"), ("page", "1")])
            .send()
            .await
            .map_err(request_error)?;
        let search: ServiceAccountSearch =
            decode(response, "GET", "/api/serviceaccounts/search").await?;
        Ok(search
            .service_accounts
            .into_iter()
            .find(|account| account.name == name))
    }

    async fn create_service_account(
        &self,
        name: &str,
        role: &str,
    ) -> Result<ServiceAccount, Error> {
        let response = self
            .request(Method::POST, "/api/serviceaccounts")
            .json(&json!({
                "name": name,
                "role": role,
                "isDisabled": false
            }))
            .send()
            .await
            .map_err(request_error)?;
        decode(response, "POST", "/api/serviceaccounts").await
    }

    async fn update_service_account(
        &self,
        account: &ServiceAccount,
        role: &str,
    ) -> Result<ServiceAccount, Error> {
        let path = format!("/api/serviceaccounts/{}", account.id);
        let response = self
            .request(Method::PATCH, &path)
            .json(&json!({
                "name": account.name,
                "role": role,
                "isDisabled": false
            }))
            .send()
            .await
            .map_err(request_error)?;
        expect_success(response, "PATCH", &path).await?;
        Ok(ServiceAccount {
            id: account.id,
            name: account.name.clone(),
            role: role.to_string(),
            is_disabled: false,
        })
    }

    async fn service_account_tokens(
        &self,
        account_id: i64,
    ) -> Result<Vec<ServiceAccountToken>, Error> {
        let path = format!("/api/serviceaccounts/{account_id}/tokens");
        let response = self
            .request(Method::GET, &path)
            .send()
            .await
            .map_err(request_error)?;
        decode(response, "GET", &path).await
    }

    async fn delete_service_account_token(
        &self,
        account_id: i64,
        token_id: i64,
    ) -> Result<(), Error> {
        let path = format!("/api/serviceaccounts/{account_id}/tokens/{token_id}");
        let response = self
            .request(Method::DELETE, &path)
            .send()
            .await
            .map_err(request_error)?;
        expect_success(response, "DELETE", &path).await
    }

    async fn create_service_account_token(
        &self,
        account_id: i64,
        token_name: &str,
    ) -> Result<String, Error> {
        let path = format!("/api/serviceaccounts/{account_id}/tokens");
        let response = self
            .request(Method::POST, &path)
            .json(&json!({ "name": token_name }))
            .send()
            .await
            .map_err(request_error)?;
        let created: CreatedToken = decode(response, "POST", &path).await?;
        Ok(created.key)
    }

    fn request(&self, method: Method, path: &str) -> reqwest::RequestBuilder {
        self.http
            .request(method, self.url(path))
            .basic_auth(&self.admin_user, Some(&self.admin_password))
    }

    fn url(&self, path: &str) -> String {
        format!("{}/{}", self.base_url, path.trim_start_matches('/'))
    }
}

async fn decode<T>(response: Response, method: &str, path: &str) -> Result<T, Error>
where
    T: for<'de> Deserialize<'de>,
{
    let status = response.status();
    let body = response.text().await.map_err(request_error)?;
    if !status.is_success() {
        return Err(api_error(method, path, status, &body));
    }
    serde_json::from_str(&body).map_err(|error| {
        std::io::Error::other(format!(
            "Grafana {method} {path} returned invalid JSON: {error}"
        ))
        .into()
    })
}

async fn expect_success(response: Response, method: &str, path: &str) -> Result<(), Error> {
    let status = response.status();
    if status.is_success() {
        return Ok(());
    }
    let body = response.text().await.map_err(request_error)?;
    Err(api_error(method, path, status, &body))
}

fn api_error(method: &str, path: &str, status: StatusCode, body: &str) -> Error {
    let body = body.chars().take(500).collect::<String>();
    std::io::Error::other(format!(
        "Grafana {method} {path} failed with {status}: {body}"
    ))
    .into()
}

fn request_error(error: reqwest::Error) -> Error {
    std::io::Error::other(format!("Grafana HTTP request failed: {error}")).into()
}

#[cfg(test)]
mod tests {
    use super::ServiceAccountSearch;

    #[test]
    fn parses_service_account_search_response() {
        let body = r#"{
          "totalCount": 1,
          "serviceAccounts": [
            {"id": 7, "name": "ahara-dashboard-deployer", "role": "Editor"}
          ]
        }"#;

        let parsed: ServiceAccountSearch = serde_json::from_str(body).unwrap();

        assert_eq!(parsed.service_accounts.len(), 1);
        assert_eq!(parsed.service_accounts[0].id, 7);
        assert_eq!(parsed.service_accounts[0].name, "ahara-dashboard-deployer");
        assert_eq!(parsed.service_accounts[0].role, "Editor");
        assert!(!parsed.service_accounts[0].is_disabled);
    }
}
