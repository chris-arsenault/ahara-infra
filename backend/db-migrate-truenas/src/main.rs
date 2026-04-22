use aws_sdk_ssm::Client as SsmClient;
use lambda_runtime::{service_fn, Error, LambdaEvent};
use rand::Rng;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use std::error::Error as StdError;
use std::time::Instant;
use tokio_postgres::{Client, NoTls};
use tracing::{error, info};

#[derive(Deserialize)]
struct ProjectConfig {
    db_name: String,
}

#[derive(Deserialize)]
struct Request {
    project: String,
}

#[derive(Serialize)]
struct Response {
    project: String,
    db_name: String,
    created: bool,
}

fn get_project_map() -> HashMap<String, ProjectConfig> {
    serde_json::from_str(&env::var("PROJECT_MAP").expect("PROJECT_MAP not set"))
        .expect("Invalid PROJECT_MAP JSON")
}

fn generate_password() -> String {
    const CHARSET: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    let mut rng = rand::thread_rng();
    (0..32)
        .map(|_| CHARSET[rng.gen_range(0..CHARSET.len())] as char)
        .collect()
}

fn postgres_connect_error(prefix: &str, error: &tokio_postgres::Error, start: Instant) -> String {
    let mut msg = format!("{prefix} after {}ms: {error}", start.elapsed().as_millis());
    let err: &dyn StdError = error;
    let mut source = err.source();
    while let Some(s) = source {
        msg.push_str(&format!(" caused by: {s}"));
        source = s.source();
    }
    msg
}

async fn fetch_ssm_value(ssm: &SsmClient, name: &str, label: &str) -> Result<String, Error> {
    ssm.get_parameter()
        .name(name)
        .with_decryption(true)
        .send()
        .await
        .map_err(|e| format!("Failed to read {label} from SSM: {e}"))?
        .parameter()
        .and_then(|p| p.value().map(|v| v.to_string()))
        .ok_or_else(|| format!("SSM param {name} has no value").into())
}

async fn fetch_admin_credentials(ssm: &SsmClient) -> Result<(String, String), Error> {
    let t1 = Instant::now();
    let user = fetch_ssm_value(ssm, "/ahara/truenas/pg-admin-user", "admin user").await?;
    info!(
        elapsed_ms = t1.elapsed().as_millis(),
        user = user,
        "Step 2: SSM admin user retrieved"
    );

    let t2 = Instant::now();
    let password =
        fetch_ssm_value(ssm, "/ahara/truenas/pg-admin-password", "admin password").await?;
    info!(
        elapsed_ms = t2.elapsed().as_millis(),
        "Step 3: SSM admin password retrieved"
    );

    Ok((user, password))
}

fn spawn_connection_task(
    connection: tokio_postgres::Connection<
        tokio_postgres::Socket,
        tokio_postgres::tls::NoTlsStream,
    >,
) {
    tokio::spawn(async move {
        if let Err(e) = connection.await {
            error!("DB connection error: {e}");
        }
    });
}

fn postgres_env() -> Result<(String, String), Error> {
    let host = env::var("PG_HOST")?;
    let port = env::var("PG_PORT").unwrap_or_else(|_| "5432".into());
    Ok((host, port))
}

fn admin_connstr(host: &str, port: &str, user: &str, password: &str) -> String {
    format!("host={host} port={port} user={user} password={password} dbname=postgres")
}

async fn connect_postgres(connstr: &str, error_prefix: &str) -> Result<Client, Error> {
    let connect_start = Instant::now();
    let (client, connection) = tokio_postgres::connect(connstr, NoTls)
        .await
        .map_err(|e| postgres_connect_error(error_prefix, &e, connect_start))?;
    spawn_connection_task(connection);
    Ok(client)
}

async fn admin_connection_context(
    ssm: &SsmClient,
    start: Instant,
) -> Result<(String, String, String), Error> {
    let (host, port) = postgres_env()?;
    info!(host = host, port = port, "Step 1: env vars read");

    let (user, password) = fetch_admin_credentials(ssm).await?;
    info!(
        host = host,
        port = port,
        user = user,
        total_ssm_ms = start.elapsed().as_millis(),
        "Step 4: Attempting Postgres connect"
    );
    let connstr = admin_connstr(&host, &port, &user, &password);
    Ok((host, port, connstr))
}

async fn connect_admin(ssm: &SsmClient) -> Result<Client, Error> {
    let t0 = Instant::now();
    let (_host, _port, connstr) = admin_connection_context(ssm, t0).await?;
    let client = connect_postgres(&connstr, "Postgres connect failed").await?;
    info!("Step 5: Postgres connected");
    info!(
        total_ms = t0.elapsed().as_millis(),
        "Step 6: connect_admin complete"
    );
    Ok(client)
}

async fn create_database_if_missing(
    pg: &Client,
    project: &str,
    db_name: &str,
) -> Result<bool, Error> {
    let db_rows = pg
        .query("SELECT 1 FROM pg_database WHERE datname = $1", &[&db_name])
        .await
        .map_err(|e| format!("Failed to query pg_database: {e}"))?;
    if !db_rows.is_empty() {
        return Ok(false);
    }

    info!(project, db = db_name, "Creating database");
    pg.batch_execute(&format!("CREATE DATABASE \"{db_name}\""))
        .await
        .map_err(|e| format!("Failed to CREATE DATABASE {db_name}: {e}"))?;
    Ok(true)
}

async fn create_role_if_missing(
    pg: &Client,
    ssm: &SsmClient,
    project: &str,
    db_name: &str,
    role_name: &str,
    ssm_prefix: &str,
) -> Result<bool, Error> {
    let role_rows = pg
        .query("SELECT 1 FROM pg_roles WHERE rolname = $1", &[&role_name])
        .await
        .map_err(|e| format!("Failed to query pg_roles: {e}"))?;
    if !role_rows.is_empty() {
        return Ok(false);
    }

    let password = generate_password();
    info!(project, role = role_name, "Creating application role");

    pg.batch_execute(&format!(
        "CREATE ROLE \"{role_name}\" LOGIN PASSWORD '{password}'"
    ))
    .await
    .map_err(|e| format!("Failed to CREATE ROLE {role_name}: {e}"))?;

    ssm.put_parameter()
        .name(format!("{ssm_prefix}/username"))
        .r#type(aws_sdk_ssm::types::ParameterType::String)
        .value(role_name)
        .overwrite(true)
        .send()
        .await?;

    ssm.put_parameter()
        .name(format!("{ssm_prefix}/password"))
        .r#type(aws_sdk_ssm::types::ParameterType::SecureString)
        .value(&password)
        .overwrite(true)
        .send()
        .await?;

    ssm.put_parameter()
        .name(format!("{ssm_prefix}/database"))
        .r#type(aws_sdk_ssm::types::ParameterType::String)
        .value(db_name)
        .overwrite(true)
        .send()
        .await?;

    info!(project, role = role_name, "Credentials published to SSM");
    Ok(true)
}

async fn connect_project_database(ssm: &SsmClient, db_name: &str) -> Result<Client, Error> {
    let host = env::var("PG_HOST")?;
    let port = env::var("PG_PORT").unwrap_or_else(|_| "5432".into());
    let (user, password) = fetch_admin_credentials(ssm).await?;
    let connstr =
        format!("host={host} port={port} user={user} password={password} dbname={db_name}");
    let connect_start = Instant::now();
    let (db, connection) = tokio_postgres::connect(&connstr, NoTls)
        .await
        .map_err(|e| {
            postgres_connect_error(
                &format!("Failed to connect to database {db_name}"),
                &e,
                connect_start,
            )
        })?;
    spawn_connection_task(connection);
    Ok(db)
}

async fn grant_project_schema_access(
    db: &Client,
    db_name: &str,
    role_name: &str,
) -> Result<(), Error> {
    db.batch_execute(&format!(
        "GRANT ALL ON SCHEMA public TO \"{role_name}\";
         ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"{role_name}\";
         ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"{role_name}\";
         GRANT ALL ON ALL TABLES IN SCHEMA public TO \"{role_name}\";
         GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO \"{role_name}\";"
    ))
    .await
    .map_err(|e| format!("Failed to set schema grants for {role_name} on {db_name}: {e}").into())
}

async fn ensure_database(
    pg: &Client,
    ssm: &SsmClient,
    project: &str,
    config: &ProjectConfig,
) -> Result<Response, Error> {
    let db_name = &config.db_name;
    let role_name = format!("{project}_app");
    let ssm_prefix = format!("/ahara/truenas-db/{project}");
    let mut created = create_database_if_missing(pg, project, db_name).await?;
    created |= create_role_if_missing(pg, ssm, project, db_name, &role_name, &ssm_prefix).await?;

    pg.batch_execute(&format!(
        "GRANT ALL PRIVILEGES ON DATABASE \"{db_name}\" TO \"{role_name}\""
    ))
    .await
    .map_err(|e| format!("Failed to GRANT on database {db_name}: {e}"))?;

    let db = connect_project_database(ssm, db_name).await?;
    grant_project_schema_access(&db, db_name, &role_name).await?;

    info!(project, db = db_name, role = role_name, "Database ready");

    Ok(Response {
        project: project.to_string(),
        db_name: db_name.to_string(),
        created,
    })
}

async fn handler(event: LambdaEvent<serde_json::Value>) -> Result<serde_json::Value, Error> {
    let (payload, _ctx) = event.into_parts();
    info!(event = %payload, "TrueNAS DB manage invoked");

    let request: Request = serde_json::from_value(payload)?;
    let project_map = get_project_map();

    let config = project_map.get(&request.project).ok_or_else(|| {
        format!(
            "Project \"{}\" not registered. Registered: {:?}",
            request.project,
            project_map.keys().collect::<Vec<_>>()
        )
    })?;

    let aws_config = aws_config::load_defaults(aws_config::BehaviorVersion::latest()).await;
    let ssm = SsmClient::new(&aws_config);

    let pg = connect_admin(&ssm).await.map_err(|e| {
        let msg = format!("Failed to connect to TrueNAS Postgres: {e}");
        error!(error = msg, "Connection failed");
        msg
    })?;

    let response = ensure_database(&pg, &ssm, &request.project, config)
        .await
        .map_err(|e| {
            let msg = format!("ensure_database failed for {}: {e}", request.project);
            error!(error = msg, "Database setup failed");
            msg
        })?;
    Ok(serde_json::to_value(response)?)
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

    lambda_runtime::run(service_fn(handler)).await
}
