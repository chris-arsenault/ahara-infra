use aws_sdk_ssm::Client as SsmClient;
use ci_ingest::migration::migrate_legacy_builds;
use lambda_runtime::{service_fn, Error, LambdaEvent};
use serde_json::{json, Value};
use std::env;
use tokio_postgres::{Client, NoTls};
use tracing::{error, info};

const RDS_CA_BUNDLE: &[u8] = include_bytes!("../../../certs/rds-global-bundle.pem");

fn make_tls_connector() -> tokio_postgres_rustls::MakeRustlsConnect {
    let mut root_store = rustls::RootCertStore::empty();
    let certs: Vec<rustls_pki_types::CertificateDer<'_>> =
        rustls_pemfile::certs(&mut &RDS_CA_BUNDLE[..])
            .collect::<Result<Vec<_>, _>>()
            .expect("Failed to parse RDS CA bundle");
    for cert in certs {
        root_store.add(cert).expect("Failed to add RDS CA cert");
    }
    let config = rustls::ClientConfig::builder()
        .with_root_certificates(root_store)
        .with_no_client_auth();
    tokio_postgres_rustls::MakeRustlsConnect::new(config)
}

async fn fetch_credentials(ssm: &SsmClient, prefix: &str) -> Result<(String, String), Error> {
    let user = ssm
        .get_parameter()
        .name(format!("{prefix}/username"))
        .send()
        .await?
        .parameter()
        .and_then(|parameter| parameter.value())
        .ok_or("database username parameter is empty")?
        .to_string();
    let password = ssm
        .get_parameter()
        .name(format!("{prefix}/password"))
        .with_decryption(true)
        .send()
        .await?
        .parameter()
        .and_then(|parameter| parameter.value())
        .ok_or("database password parameter is empty")?
        .to_string();
    Ok((user, password))
}

async fn connect_source(ssm: &SsmClient) -> Result<Client, Error> {
    let host = env::var("SOURCE_DB_HOST")?;
    let port = env::var("SOURCE_DB_PORT").unwrap_or_else(|_| "5432".into());
    let db_name = env::var("SOURCE_DB_NAME")?;
    let prefix = env::var("SOURCE_DB_SSM_PREFIX")?;
    let (user, password) = fetch_credentials(ssm, &prefix).await?;
    let connstr = format!(
        "host={host} port={port} user={user} password={password} dbname={db_name} sslmode=require"
    );
    let (client, connection) = tokio_postgres::connect(&connstr, make_tls_connector()).await?;
    tokio::spawn(async move {
        if let Err(error) = connection.await {
            error!(%error, "Legacy RDS connection failed");
        }
    });
    Ok(client)
}

async fn connect_destination(ssm: &SsmClient) -> Result<Client, Error> {
    let host = env::var("DESTINATION_DB_HOST")?;
    let port = env::var("DESTINATION_DB_PORT").unwrap_or_else(|_| "5432".into());
    let db_name = env::var("DESTINATION_DB_NAME")?;
    let prefix = env::var("DESTINATION_DB_SSM_PREFIX")?;
    let (user, password) = fetch_credentials(ssm, &prefix).await?;
    let connstr =
        format!("host={host} port={port} user={user} password={password} dbname={db_name}");
    let (client, connection) = tokio_postgres::connect(&connstr, NoTls).await?;
    tokio::spawn(async move {
        if let Err(error) = connection.await {
            error!(%error, "TrueNAS PostgreSQL connection failed");
        }
    });
    Ok(client)
}

async fn handler(event: LambdaEvent<Value>) -> Result<Value, Error> {
    let phase = event
        .payload
        .get("phase")
        .and_then(Value::as_str)
        .unwrap_or("manual");
    info!(phase, "Starting legacy CI history migration");

    let aws_config = aws_config::load_defaults(aws_config::BehaviorVersion::latest()).await;
    let ssm = SsmClient::new(&aws_config);
    let mut source = connect_source(&ssm).await?;
    let mut destination = connect_destination(&ssm).await?;
    let summary = migrate_legacy_builds(&mut source, &mut destination).await?;

    info!(
        phase,
        source_rows = summary.source_rows,
        inserted_rows = summary.inserted_rows,
        verified_rows = summary.verified_rows,
        destination_rows = summary.destination_rows,
        "Legacy CI history migration complete"
    );
    Ok(json!({
        "phase": phase,
        "status": "complete",
        "source_rows": summary.source_rows,
        "inserted_rows": summary.inserted_rows,
        "verified_rows": summary.verified_rows,
        "destination_rows": summary.destination_rows,
    }))
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    rustls::crypto::ring::default_provider()
        .install_default()
        .expect("Failed to install rustls crypto provider");

    tracing_subscriber::fmt()
        .json()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env().add_directive("info".parse()?),
        )
        .without_time()
        .init();
    lambda_runtime::run(service_fn(handler)).await
}
