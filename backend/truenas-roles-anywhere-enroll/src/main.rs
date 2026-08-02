use std::env;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use aws_config::BehaviorVersion;
use aws_sdk_ssm::Client as SsmClient;
use lambda_http::{run, service_fn, Body, Error, Request, Response};
use rcgen::string::Ia5String;
use rcgen::{
    CertificateSigningRequestParams, DistinguishedName, DnType, ExtendedKeyUsagePurpose, IsCa,
    Issuer, KeyPair, KeyUsagePurpose, SanType,
};
use serde::{Deserialize, Serialize};
use time::{Duration as TimeDuration, OffsetDateTime};
use tracing::{error, info};

#[derive(Clone)]
struct AppState {
    ssm: SsmClient,
    config: Config,
    ca_cert_pem: String,
    ca_key_pem: String,
}

#[derive(Clone)]
struct Config {
    cert_validity_days: i64,
    entry_role_arn: String,
    profile_arn: String,
    trust_anchor_arn: String,
}

impl Config {
    fn from_env() -> Result<Self, Error> {
        Ok(Self {
            cert_validity_days: env::var("CERT_VALIDITY_DAYS")
                .unwrap_or_else(|_| "90".into())
                .parse()?,
            entry_role_arn: env::var("ENTRY_ROLE_ARN")?,
            profile_arn: env::var("PROFILE_ARN")?,
            trust_anchor_arn: env::var("TRUST_ANCHOR_ARN")?,
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

/// Signs the workload CSR with the self-managed CA. Subject and extensions
/// are set server-side from the validated workload_id; nothing requested in
/// the CSR beyond its public key is honored. The URI SAN is what the entry
/// role's tag-match condition keys on, so it must be exactly the workload_id.
fn issue_certificate(
    ca_cert_pem: &str,
    ca_key_pem: &str,
    cert_validity_days: i64,
    workload_id: &str,
    project: &str,
    name: &str,
    csr_pem: &str,
) -> Result<String, Error> {
    let ca_key = KeyPair::from_pem(ca_key_pem)?;
    let issuer = Issuer::from_ca_cert_pem(ca_cert_pem, ca_key)?;

    let mut csr = CertificateSigningRequestParams::from_pem(csr_pem)?;

    let common_name: String = format!("{project}/{name}").chars().take(64).collect();
    let mut dn = DistinguishedName::new();
    dn.push(DnType::CommonName, common_name);
    dn.push(DnType::OrganizationName, "Ahara");
    dn.push(DnType::OrganizationalUnitName, "TrueNAS");
    csr.params.distinguished_name = dn;

    csr.params.is_ca = IsCa::ExplicitNoCa;
    csr.params.key_usages = vec![KeyUsagePurpose::DigitalSignature];
    csr.params.extended_key_usages = vec![ExtendedKeyUsagePurpose::ClientAuth];
    csr.params.subject_alt_names =
        vec![SanType::URI(Ia5String::try_from(workload_id.to_string())?)];
    csr.params.use_authority_key_identifier_extension = true;

    let now = OffsetDateTime::now_utc();
    csr.params.not_before = now - TimeDuration::minutes(5);
    csr.params.not_after = now + TimeDuration::days(cert_validity_days);

    let certificate = csr.signed_by(&issuer)?;
    Ok(certificate.pem())
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
    let certificate_pem = issue_certificate(
        &state.ca_cert_pem,
        &state.ca_key_pem,
        state.config.cert_validity_days,
        &request.workload_id,
        project,
        name,
        &request.csr_pem,
    )?;

    Ok(EnrollResponse {
        certificate_pem,
        certificate_chain_pem: state.ca_cert_pem.clone(),
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
    let ssm = SsmClient::new(&aws_config);

    let ca_cert_param = env::var("CA_CERT_PARAM")?;
    let ca_key_param = env::var("CA_KEY_PARAM")?;
    let ca_cert_pem = get_parameter(&ssm, &ca_cert_param, false).await?;
    let ca_key_pem = get_parameter(&ssm, &ca_key_param, true).await?;

    let state = Arc::new(AppState {
        ssm,
        config: Config::from_env()?,
        ca_cert_pem,
        ca_key_pem,
    });

    run(service_fn(move |request| {
        let state = Arc::clone(&state);
        async move { handler(request, state).await }
    }))
    .await
}

#[cfg(test)]
mod tests {
    use super::*;
    use x509_parser::prelude::{FromDer, GeneralName, X509Certificate};

    const CA_KEY_PEM: &str = include_str!("../tests/fixtures/ca-key.pem");
    const CA_CERT_PEM: &str = include_str!("../tests/fixtures/ca-cert.pem");
    const WORKLOAD_CSR_PEM: &str = include_str!("../tests/fixtures/workload.csr");

    #[test]
    fn signs_rsa_csr_with_ec_ca() {
        let workload_id = "spiffe://ahara/truenas/house-sensors/raw-archive";
        let cert_pem = issue_certificate(
            CA_CERT_PEM,
            CA_KEY_PEM,
            90,
            workload_id,
            "house-sensors",
            "raw-archive",
            WORKLOAD_CSR_PEM,
        )
        .expect("issuing a certificate from an RSA CSR must succeed");

        let (_, cert_pem_block) =
            x509_parser::pem::parse_x509_pem(cert_pem.as_bytes()).expect("issued cert must be PEM");
        let (_, cert) =
            X509Certificate::from_der(&cert_pem_block.contents).expect("issued cert must parse");

        let (_, ca_pem_block) = x509_parser::pem::parse_x509_pem(CA_CERT_PEM.as_bytes()).unwrap();
        let (_, ca) = X509Certificate::from_der(&ca_pem_block.contents).unwrap();
        cert.verify_signature(Some(ca.public_key()))
            .expect("issued cert must verify against the CA public key");

        assert_eq!(cert.issuer(), ca.subject());
        assert!(!cert.is_ca());

        let san = cert
            .subject_alternative_name()
            .expect("SAN extension must parse")
            .expect("SAN extension must be present");
        assert_eq!(san.value.general_names, vec![GeneralName::URI(workload_id)]);

        let eku = cert
            .extended_key_usage()
            .expect("EKU extension must parse")
            .expect("EKU extension must be present");
        assert!(eku.value.client_auth);

        let ku = cert
            .key_usage()
            .expect("KU extension must parse")
            .expect("KU extension must be present");
        assert!(ku.value.digital_signature());
    }

    #[test]
    fn rejects_malformed_workload_ids() {
        assert!(parse_workload_id("spiffe://ahara/truenas/proj/name").is_ok());
        assert!(parse_workload_id("spiffe://other/truenas/proj/name").is_err());
        assert!(parse_workload_id("spiffe://ahara/truenas/proj").is_err());
        assert!(parse_workload_id("spiffe://ahara/truenas/proj/name/extra").is_err());
        assert!(parse_workload_id("spiffe://ahara/truenas/Proj/name").is_err());
    }
}
