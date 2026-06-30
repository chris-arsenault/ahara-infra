use std::env;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use aws_config::BehaviorVersion;
use aws_sdk_acmpca::primitives::Blob;
use aws_sdk_acmpca::types::{
    ApiPassthrough, Asn1Subject, ExtendedKeyUsage, ExtendedKeyUsageType, Extensions, GeneralName,
    KeyUsage, SigningAlgorithm, Validity, ValidityPeriodType,
};
use aws_sdk_acmpca::Client as AcmPcaClient;
use aws_sdk_ssm::Client as SsmClient;
use lambda_http::{run, service_fn, Body, Error, Request, Response};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

#[derive(Clone)]
struct AppState {
    acmpca: AcmPcaClient,
    ssm: SsmClient,
    config: Config,
}

#[derive(Clone)]
struct Config {
    ca_arn: String,
    cert_validity_days: i64,
    entry_role_arn: String,
    profile_arn: String,
    trust_anchor_arn: String,
    partition: String,
}

impl Config {
    fn from_env() -> Result<Self, Error> {
        Ok(Self {
            ca_arn: env::var("CA_ARN")?,
            cert_validity_days: env::var("CERT_VALIDITY_DAYS")
                .unwrap_or_else(|_| "90".into())
                .parse()?,
            entry_role_arn: env::var("ENTRY_ROLE_ARN")?,
            profile_arn: env::var("PROFILE_ARN")?,
            trust_anchor_arn: env::var("TRUST_ANCHOR_ARN")?,
            partition: env::var("AWS_PARTITION").unwrap_or_else(|_| "aws".into()),
        })
    }
}

#[derive(Deserialize)]
struct EnrollRequest {
    workload_id: String,
    token: String,
    csr_pem: String,
}

#[derive(Deserialize)]
struct StoredToken {
    token: String,
    expires_at: Option<u64>,
}

#[derive(Serialize)]
struct EnrollResponse {
    certificate_arn: String,
    certificate_pem: String,
    certificate_chain_pem: String,
    workload_id: String,
    role_arn: String,
    trust_anchor_arn: String,
    profile_arn: String,
    entry_role_arn: String,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

fn json_response(status: u16, value: impl Serialize) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .header("cache-control", "no-store")
        .body(Body::Text(serde_json::to_string(&value)?))?)
}

fn parse_workload_id(workload_id: &str) -> Result<(&str, &str), String> {
    let prefix = "spiffe://ahara/truenas/";
    let rest = workload_id
        .strip_prefix(prefix)
        .ok_or_else(|| "invalid workload_id".to_string())?;
    let mut parts = rest.split('/');
    let project = parts
        .next()
        .filter(|p| is_slug(p))
        .ok_or_else(|| "invalid workload_id project".to_string())?;
    let name = parts
        .next()
        .filter(|p| is_slug(p))
        .ok_or_else(|| "invalid workload_id name".to_string())?;
    if parts.next().is_some() {
        return Err("invalid workload_id".into());
    }
    Ok((project, name))
}

fn is_slug(value: &str) -> bool {
    let mut chars = value.chars();
    match chars.next() {
        Some(c) if c.is_ascii_lowercase() || c.is_ascii_digit() => {}
        _ => return false,
    }
    chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

fn now_epoch_seconds() -> Result<u64, Error> {
    Ok(SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs())
}

async fn get_parameter(ssm: &SsmClient, name: &str, decrypt: bool) -> Result<String, Error> {
    Ok(ssm
        .get_parameter()
        .name(name)
        .set_with_decryption(Some(decrypt))
        .send()
        .await?
        .parameter()
        .and_then(|p| p.value())
        .ok_or_else(|| format!("SSM param {name} has no value"))?
        .to_string())
}

async fn registered_role_arn(ssm: &SsmClient, project: &str, name: &str) -> Result<String, Error> {
    let path = format!("/ahara/truenas-roles-anywhere/workloads/{project}/{name}/role-arn");
    get_parameter(ssm, &path, false).await
}

async fn validate_token(
    ssm: &SsmClient,
    project: &str,
    name: &str,
    token: &str,
) -> Result<String, Error> {
    let path = format!("/ahara/truenas-roles-anywhere/enrollment/{project}/{name}/token");
    let value = get_parameter(ssm, &path, true).await?;
    let stored: StoredToken = serde_json::from_str(&value).unwrap_or(StoredToken {
        token: value,
        expires_at: None,
    });
    if let Some(expires_at) = stored.expires_at {
        if expires_at < now_epoch_seconds()? {
            return Err("enrollment token expired".into());
        }
    }
    if stored.token != token {
        return Err("invalid enrollment token".into());
    }
    Ok(path)
}

async fn issue_certificate(
    acmpca: &AcmPcaClient,
    config: &Config,
    workload_id: &str,
    project: &str,
    name: &str,
    csr_pem: &str,
) -> Result<(String, String, String), Error> {
    let common_name = format!("{project}/{name}");
    let common_name = common_name.chars().take(64).collect::<String>();
    let template_arn = format!(
        "arn:{}:acm-pca:::template/BlankEndEntityCertificate_APIPassthrough/V1",
        config.partition
    );

    let issued = acmpca
        .issue_certificate()
        .certificate_authority_arn(&config.ca_arn)
        .csr(Blob::new(csr_pem.as_bytes()))
        .signing_algorithm(SigningAlgorithm::Sha256Withrsa)
        .validity(
            Validity::builder()
                .r#type(ValidityPeriodType::Days)
                .value(config.cert_validity_days)
                .build()?,
        )
        .template_arn(template_arn)
        .api_passthrough(
            ApiPassthrough::builder()
                .subject(
                    Asn1Subject::builder()
                        .common_name(common_name)
                        .organization("Ahara")
                        .organizational_unit("TrueNAS")
                        .build(),
                )
                .extensions(
                    Extensions::builder()
                        .key_usage(KeyUsage::builder().digital_signature(true).build())
                        .extended_key_usage(
                            ExtendedKeyUsage::builder()
                                .extended_key_usage_type(ExtendedKeyUsageType::ClientAuth)
                                .build(),
                        )
                        .subject_alternative_names(
                            GeneralName::builder()
                                .uniform_resource_identifier(workload_id)
                                .build(),
                        )
                        .build(),
                )
                .build(),
        )
        .send()
        .await?;

    let certificate_arn = issued
        .certificate_arn()
        .ok_or("ACM PCA did not return certificate ARN")?
        .to_string();

    let mut last_error = None;
    for _ in 0..20 {
        match acmpca
            .get_certificate()
            .certificate_authority_arn(&config.ca_arn)
            .certificate_arn(&certificate_arn)
            .send()
            .await
        {
            Ok(cert) => {
                let certificate = cert.certificate().unwrap_or_default().to_string();
                let chain = cert.certificate_chain().unwrap_or_default().to_string();
                return Ok((certificate_arn, certificate, chain));
            }
            Err(error) => {
                last_error = Some(error.to_string());
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
        }
    }

    Err(format!(
        "certificate was not issued before timeout: {}",
        last_error.unwrap_or_else(|| "unknown error".into())
    )
    .into())
}

async fn enroll(request: EnrollRequest, state: &AppState) -> Result<EnrollResponse, Error> {
    let (project, name) = parse_workload_id(&request.workload_id)?;
    let role_arn = registered_role_arn(&state.ssm, project, name).await?;
    let token_path = validate_token(&state.ssm, project, name, &request.token).await?;
    state
        .ssm
        .delete_parameter()
        .name(token_path.as_str())
        .send()
        .await?;
    let (certificate_arn, certificate_pem, certificate_chain_pem) = issue_certificate(
        &state.acmpca,
        &state.config,
        &request.workload_id,
        project,
        name,
        &request.csr_pem,
    )
    .await?;

    Ok(EnrollResponse {
        certificate_arn,
        certificate_pem,
        certificate_chain_pem,
        workload_id: request.workload_id,
        role_arn,
        trust_anchor_arn: state.config.trust_anchor_arn.clone(),
        profile_arn: state.config.profile_arn.clone(),
        entry_role_arn: state.config.entry_role_arn.clone(),
    })
}

async fn handler(request: Request, state: Arc<AppState>) -> Result<Response<Body>, Error> {
    if request.method().as_str() != "POST" {
        return json_response(
            405,
            ErrorResponse {
                error: "method not allowed".into(),
            },
        );
    }

    let body = std::str::from_utf8(request.body().as_ref()).unwrap_or("{}");
    let enroll_request = match serde_json::from_str::<EnrollRequest>(body) {
        Ok(request) => request,
        Err(error) => {
            return json_response(
                400,
                ErrorResponse {
                    error: format!("invalid request: {error}"),
                },
            );
        }
    };

    info!(
        workload_id = enroll_request.workload_id,
        "enrollment request"
    );
    match enroll(enroll_request, &state).await {
        Ok(response) => json_response(200, response),
        Err(error) => {
            error!(%error, "enrollment failed");
            json_response(
                403,
                ErrorResponse {
                    error: error.to_string(),
                },
            )
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .json()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env().add_directive("info".parse()?),
        )
        .without_time()
        .init();

    let aws_config = aws_config::load_defaults(BehaviorVersion::latest()).await;
    let state = Arc::new(AppState {
        acmpca: AcmPcaClient::new(&aws_config),
        ssm: SsmClient::new(&aws_config),
        config: Config::from_env()?,
    });

    run(service_fn(move |request| {
        let state = Arc::clone(&state);
        async move { handler(request, state).await }
    }))
    .await
}
