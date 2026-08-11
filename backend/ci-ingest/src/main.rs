mod db;

use aws_sdk_ssm::Client as SsmClient;
use db::{BatchReport, BuildReport, QualityCompleteReport, QualityScanReport};
use lambda_http::{run, service_fn, Body, Error, Request, Response};
use serde::{de::DeserializeOwned, Serialize};
use std::env;
use std::sync::OnceLock;
use tokio::sync::Mutex;
use tokio_postgres::{Client, NoTls};
use tracing::{error, info};

#[derive(Serialize)]
struct JsonResponse {
    #[serde(skip_serializing_if = "Option::is_none")]
    ok: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    accepted: Option<usize>,
}

static DB: OnceLock<Mutex<Option<Client>>> = OnceLock::new();
const MAX_BODY_BYTES: usize = 900_000;

async fn get_client() -> Result<Client, Error> {
    let host = env::var("DB_HOST")?;
    let port = env::var("DB_PORT").unwrap_or_else(|_| "5432".into());
    let db_name = env::var("DB_NAME")?;
    let ssm_prefix = env::var("DB_SSM_PREFIX")?;

    let aws_config = aws_config::load_defaults(aws_config::BehaviorVersion::latest()).await;
    let ssm = SsmClient::new(&aws_config);

    let user = ssm
        .get_parameter()
        .name(format!("{ssm_prefix}/username"))
        .send()
        .await?
        .parameter()
        .ok_or("SSM param not found")?
        .value()
        .ok_or("empty value")?
        .to_string();

    let password = ssm
        .get_parameter()
        .name(format!("{ssm_prefix}/password"))
        .with_decryption(true)
        .send()
        .await?
        .parameter()
        .ok_or("empty value")?
        .value()
        .ok_or("empty value")?
        .to_string();

    let connstr =
        format!("host={host} port={port} user={user} password={password} dbname={db_name}");
    let (client, connection) = tokio_postgres::connect(&connstr, NoTls).await?;
    tokio::spawn(async move {
        if let Err(e) = connection.await {
            error!("DB connection error: {e}");
        }
    });
    db::init_schema(&client).await?;
    Ok(client)
}

async fn ensure_client() -> Result<tokio::sync::MutexGuard<'static, Option<Client>>, Error> {
    let mutex = DB.get_or_init(|| Mutex::new(None));
    let mut guard = mutex.lock().await;
    if guard.is_none() {
        *guard = Some(get_client().await?);
    }
    Ok(guard)
}

fn json_response(status: u16, body: impl Serialize) -> Result<Response<Body>, Error> {
    Ok(Response::builder()
        .status(status)
        .header("Content-Type", "application/json")
        .body(Body::Text(serde_json::to_string(&body)?))?)
}

fn parse_body<T: DeserializeOwned>(req: &Request) -> Result<T, Error> {
    if req.body().as_ref().len() > MAX_BODY_BYTES {
        return Err("Request body exceeds 900000 bytes".into());
    }
    Ok(serde_json::from_slice(req.body().as_ref())?)
}

fn is_authorized(req: &Request) -> bool {
    let Ok(token) = env::var("INGEST_TOKEN") else {
        return true;
    };
    let auth = req
        .headers()
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        .unwrap_or("");
    auth.strip_prefix("Bearer ").unwrap_or("") == token
}

fn error_response(status: u16, message: &str) -> Result<Response<Body>, Error> {
    json_response(
        status,
        JsonResponse {
            ok: None,
            error: Some(message.into()),
            accepted: None,
        },
    )
}

fn ok_response(accepted: Option<usize>) -> Result<Response<Body>, Error> {
    json_response(
        200,
        JsonResponse {
            ok: Some(true),
            error: None,
            accepted,
        },
    )
}

async fn handler(req: Request) -> Result<Response<Body>, Error> {
    let method = req.method().as_str();
    let path = req.uri().path();

    info!(method, path, "Request");

    if method == "POST" && !is_authorized(&req) {
        return error_response(401, "Unauthorized");
    }

    match (method, path) {
        ("POST", "/api/ci/report") => {
            let report: BuildReport = parse_body(&req)?;

            if let Err(msg) = db::validate_report(&report) {
                return error_response(400, msg);
            }

            let guard = ensure_client().await?;
            let client = guard.as_ref().expect("database client initialized");
            db::upsert_build(client, &report).await?;
            ok_response(None)
        }

        ("POST", "/api/ci/batch") => {
            let batch: BatchReport = parse_body(&req)?;
            if let Err(msg) = db::validate_batch(&batch) {
                return error_response(400, msg);
            }

            let accepted = batch.len();
            let guard = ensure_client().await?;
            let client = guard.as_ref().expect("database client initialized");
            db::ingest_batch(client, &batch).await?;
            ok_response(Some(accepted))
        }

        ("POST", "/api/ci/quality/start") => {
            let scan: QualityScanReport = parse_body(&req)?;
            if scan.scan_id.is_empty() || scan.run_id.is_empty() || scan.repo.is_empty() {
                return error_response(400, "Missing required scan fields");
            }

            let guard = ensure_client().await?;
            let client = guard.as_ref().expect("database client initialized");
            db::start_quality_scan(client, &scan).await?;
            ok_response(None)
        }

        ("POST", "/api/ci/quality/complete") => {
            let report: QualityCompleteReport = parse_body(&req)?;
            if report.scan_id.is_empty() || report.status.is_empty() {
                return error_response(400, "Missing required completion fields");
            }

            let guard = ensure_client().await?;
            let client = guard.as_ref().expect("database client initialized");
            if db::complete_quality_scan(client, &report).await? == 0 {
                return error_response(404, "Quality scan not found");
            }
            ok_response(None)
        }

        ("GET", "/api/ci/health") => {
            let _guard = ensure_client().await?;
            ok_response(None)
        }

        _ => error_response(404, "Not found"),
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

    run(service_fn(handler)).await
}
