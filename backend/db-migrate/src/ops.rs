use crate::storage::{CredentialStore, FileStore};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use tokio_postgres::Client;
use tracing::{error, info, warn};

pub const LOCAL_TRACKING: &str = "
CREATE TABLE IF NOT EXISTS schema_migrations (
  id SERIAL PRIMARY KEY,
  filename TEXT NOT NULL UNIQUE,
  checksum TEXT NOT NULL,
  noop BOOLEAN NOT NULL DEFAULT FALSE,
  comment TEXT,
  applied_at TIMESTAMPTZ DEFAULT NOW(),
  duration_ms INTEGER
);
";

pub const OPS_SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS migration_audit (
  id SERIAL PRIMARY KEY,
  project TEXT NOT NULL,
  operation TEXT NOT NULL,
  filename TEXT,
  checksum TEXT,
  status TEXT NOT NULL,
  comment TEXT,
  error_message TEXT,
  duration_ms INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_project ON migration_audit (project, created_at DESC);

CREATE TABLE IF NOT EXISTS seed_runs (
  id SERIAL PRIMARY KEY,
  project TEXT NOT NULL,
  filename TEXT NOT NULL,
  checksum TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_seed_project ON seed_runs (project, created_at DESC);
";

#[derive(Deserialize)]
pub struct ProjectConfig {
    pub db_name: String,
}

#[derive(Serialize, Default, Debug)]
pub struct Response {
    pub operation: String,
    pub project: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub applied: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rolled_back: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub baselined: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_ms: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub db: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub comment: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
}

pub struct AuditEntry<'a> {
    pub project: &'a str,
    pub operation: &'a str,
    pub filename: Option<&'a str>,
    pub checksum: Option<&'a str>,
    pub status: &'a str,
    pub error_message: Option<&'a str>,
    pub duration_ms: Option<i32>,
    pub comment: Option<&'a str>,
}

pub type ConnectFn = dyn Fn(
        &str,
    ) -> std::pin::Pin<
        Box<
            dyn std::future::Future<
                    Output = Result<Client, Box<dyn std::error::Error + Send + Sync>>,
                > + Send,
        >,
    > + Send
    + Sync;

pub fn checksum(content: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(content.as_bytes());
    format!("{:x}", hasher.finalize())[..16].to_string()
}

pub fn lock_id(project: &str) -> i64 {
    let mut h: i64 = 0;
    for b in project.bytes() {
        h = h.wrapping_mul(31).wrapping_add(b as i64);
    }
    h.abs()
}

pub async fn acquire_lock(client: &Client, project: &str) -> Result<(), tokio_postgres::Error> {
    let id = lock_id(project);
    client
        .execute("SELECT pg_advisory_lock($1)", &[&id])
        .await?;
    info!(project, lock_id = id, "Lock acquired");
    Ok(())
}

pub async fn release_lock(client: &Client, project: &str) -> Result<(), tokio_postgres::Error> {
    let id = lock_id(project);
    client
        .execute("SELECT pg_advisory_unlock($1)", &[&id])
        .await?;
    Ok(())
}

pub async fn audit(ops: &Client, entry: AuditEntry<'_>) {
    if let Err(e) = ops
        .execute(
            "INSERT INTO migration_audit (project, operation, filename, checksum, status, comment, error_message, duration_ms)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
            &[
                &entry.project,
                &entry.operation,
                &entry.filename,
                &entry.checksum,
                &entry.status,
                &entry.comment,
                &entry.error_message,
                &entry.duration_ms,
            ],
        )
        .await
    {
        warn!("Audit write failed (non-fatal): {e}");
    }
}

type BoxError = Box<dyn std::error::Error + Send + Sync>;

async fn database_exists(master: &Client, db_name: &str) -> Result<bool, tokio_postgres::Error> {
    Ok(!master
        .query("SELECT 1 FROM pg_database WHERE datname = $1", &[&db_name])
        .await?
        .is_empty())
}

async fn role_exists(master: &Client, role_name: &str) -> Result<bool, tokio_postgres::Error> {
    Ok(!master
        .query("SELECT 1 FROM pg_roles WHERE rolname = $1", &[&role_name])
        .await?
        .is_empty())
}

async fn create_database_if_missing(master: &Client, db_name: &str) -> Result<(), BoxError> {
    if database_exists(master, db_name).await? {
        return Ok(());
    }

    info!(db = db_name, "Creating database");
    master
        .batch_execute(&format!("CREATE DATABASE \"{db_name}\""))
        .await?;
    Ok(())
}

async fn publish_app_credentials(
    creds: &dyn CredentialStore,
    project: &str,
    role_name: &str,
    password: &str,
    db_name: &str,
) -> Result<(), BoxError> {
    let ssm_prefix = format!("/ahara/db/{project}");
    creds
        .put_param(&format!("{ssm_prefix}/username"), role_name)
        .await?;
    creds
        .put_secret(&format!("{ssm_prefix}/password"), password)
        .await?;
    creds
        .put_param(&format!("{ssm_prefix}/database"), db_name)
        .await?;
    Ok(())
}

async fn create_app_role_if_missing(
    master: &Client,
    project: &str,
    db_name: &str,
    creds: &dyn CredentialStore,
) -> Result<String, BoxError> {
    let role_name = format!("{project}_app");
    if role_exists(master, &role_name).await? {
        return Ok(role_name);
    }

    let password = generate_password();
    info!(project, role = role_name, "Creating application role");

    master
        .batch_execute(&format!(
            "CREATE ROLE \"{role_name}\" LOGIN PASSWORD '{password}'"
        ))
        .await?;

    publish_app_credentials(creds, project, &role_name, &password, db_name).await?;

    info!(
        project,
        role = role_name,
        "App role created and credentials published"
    );
    Ok(role_name)
}

async fn create_reader_role_if_missing(
    master: &Client,
    project: &str,
    creds: &dyn CredentialStore,
) -> Result<String, BoxError> {
    let reader_name = format!("{project}_reader");
    if role_exists(master, &reader_name).await? {
        return Ok(reader_name);
    }

    let password = generate_password();
    info!(project, role = reader_name, "Creating reader role");

    master
        .batch_execute(&format!(
            "CREATE ROLE \"{reader_name}\" LOGIN PASSWORD '{password}'"
        ))
        .await?;

    let ssm_prefix = format!("/ahara/db/{project}/reader");
    creds
        .put_param(&format!("{ssm_prefix}/username"), &reader_name)
        .await?;
    creds
        .put_secret(&format!("{ssm_prefix}/password"), &password)
        .await?;

    info!(
        project,
        role = reader_name,
        "Reader role created and credentials published"
    );
    Ok(reader_name)
}

async fn grant_database_privileges(
    master: &Client,
    db_name: &str,
    role_name: &str,
    reader_name: &str,
) -> Result<(), tokio_postgres::Error> {
    master
        .batch_execute(&format!(
            "GRANT ALL PRIVILEGES ON DATABASE \"{db_name}\" TO \"{role_name}\";
             GRANT CONNECT ON DATABASE \"{db_name}\" TO \"{reader_name}\";"
        ))
        .await?;

    // Grant app role membership to admin so ALTER DEFAULT PRIVILEGES FOR ROLE works in PG16
    master
        .batch_execute(&format!("GRANT \"{role_name}\" TO CURRENT_USER"))
        .await?;
    Ok(())
}

async fn grant_schema_privileges(
    connect_fn: &ConnectFn,
    db_name: &str,
    role_name: &str,
    reader_name: &str,
) -> Result<(), BoxError> {
    let db = connect_fn(db_name).await?;
    db.batch_execute(&format!(
        "GRANT ALL ON SCHEMA public TO \"{role_name}\";
         ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"{role_name}\";
         ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"{role_name}\";
         GRANT ALL ON ALL TABLES IN SCHEMA public TO \"{role_name}\";
         GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO \"{role_name}\";"
    ))
    .await?;

    db.batch_execute(&format!(
        "GRANT USAGE ON SCHEMA public TO \"{reader_name}\";
         GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{reader_name}\";
         GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{reader_name}\";
         ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO \"{reader_name}\";
         ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO \"{reader_name}\";
         ALTER DEFAULT PRIVILEGES FOR ROLE \"{role_name}\" IN SCHEMA public GRANT SELECT ON TABLES TO \"{reader_name}\";
         ALTER DEFAULT PRIVILEGES FOR ROLE \"{role_name}\" IN SCHEMA public GRANT SELECT ON SEQUENCES TO \"{reader_name}\";"
    ))
    .await?;
    Ok(())
}

pub async fn ensure_database(
    master: &Client,
    project: &str,
    db_name: &str,
    creds: &dyn CredentialStore,
    connect_fn: &ConnectFn,
) -> Result<(), BoxError> {
    create_database_if_missing(master, db_name).await?;
    let role_name = create_app_role_if_missing(master, project, db_name, creds).await?;
    let reader_name = create_reader_role_if_missing(master, project, creds).await?;
    grant_database_privileges(master, db_name, &role_name, &reader_name).await?;
    grant_schema_privileges(connect_fn, db_name, &role_name, &reader_name).await?;
    Ok(())
}

fn generate_password() -> String {
    use rand::Rng;
    const CHARSET: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    let mut rng = rand::thread_rng();
    (0..32)
        .map(|_| CHARSET[rng.gen_range(0..CHARSET.len())] as char)
        .collect()
}

/// Run pending migrations. Core logic extracted for testability.
async fn load_applied_migrations(db: &Client) -> Result<HashMap<String, String>, BoxError> {
    let applied_rows = db
        .query("SELECT filename, checksum FROM schema_migrations", &[])
        .await?;
    Ok(applied_rows
        .iter()
        .map(|r| (r.get::<_, String>(0), r.get::<_, String>(1)))
        .collect())
}

fn validate_migration_checksum(
    applied: &HashMap<String, String>,
    filename: &str,
    checksum: &str,
) -> Result<bool, String> {
    match applied.get(filename) {
        Some(existing) if existing == checksum => Ok(false),
        Some(_) => Err(format!("Checksum mismatch for {filename}")),
        None => Ok(true),
    }
}

async fn audit_migration_checksum_error(
    ops: &Client,
    project: &str,
    filename: &str,
    checksum: &str,
    message: &str,
) {
    audit(
        ops,
        AuditEntry {
            project,
            operation: "migrate",
            filename: Some(filename),
            checksum: Some(checksum),
            status: "error",
            error_message: Some(message),
            duration_ms: None,
            comment: None,
        },
    )
    .await;
}

async fn execute_migration_sql(
    db: &Client,
    filename: &str,
    checksum: &str,
    sql: &str,
) -> Result<i32, tokio_postgres::Error> {
    let start = std::time::Instant::now();
    db.batch_execute("BEGIN").await?;
    match db.batch_execute(sql).await {
        Ok(()) => {
            let dur = start.elapsed().as_millis() as i32;
            db.execute(
                "INSERT INTO schema_migrations (filename, checksum, duration_ms) VALUES ($1, $2, $3)",
                &[&filename, &checksum, &dur],
            )
            .await?;
            db.batch_execute("COMMIT").await?;
            Ok(dur)
        }
        Err(e) => {
            db.batch_execute("ROLLBACK").await.ok();
            Err(e)
        }
    }
}

async fn audit_migration_success(
    ops: &Client,
    project: &str,
    filename: &str,
    checksum: &str,
    duration_ms: i32,
) {
    audit(
        ops,
        AuditEntry {
            project,
            operation: "migrate",
            filename: Some(filename),
            checksum: Some(checksum),
            status: "success",
            error_message: None,
            duration_ms: Some(duration_ms),
            comment: None,
        },
    )
    .await;
}

async fn audit_migration_failure(
    ops: &Client,
    project: &str,
    filename: &str,
    checksum: &str,
    message: &str,
) {
    audit(
        ops,
        AuditEntry {
            project,
            operation: "migrate",
            filename: Some(filename),
            checksum: Some(checksum),
            status: "error",
            error_message: Some(message),
            duration_ms: None,
            comment: None,
        },
    )
    .await;
}

async fn load_migration_sql_and_checksum(
    files: &dyn FileStore,
    file: &crate::storage::MigrationFile,
) -> Result<(String, String), BoxError> {
    let sql = files.read_file(&file.key).await?;
    let checksum = checksum(&sql);
    Ok((sql, checksum))
}

async fn ensure_migration_not_applied(
    ops: &Client,
    project: &str,
    filename: &str,
    checksum: &str,
    applied: &HashMap<String, String>,
) -> Result<bool, BoxError> {
    match validate_migration_checksum(applied, filename, checksum) {
        Ok(should_apply) => Ok(should_apply),
        Err(msg) => {
            audit_migration_checksum_error(ops, project, filename, checksum, &msg).await;
            Err(msg.into())
        }
    }
}

async fn run_migration_file(
    db: &Client,
    ops: &Client,
    project: &str,
    filename: &str,
    checksum: &str,
    sql: &str,
) -> Result<bool, BoxError> {
    info!(project, file = filename, "Applying");
    let result = execute_migration_sql(db, filename, checksum, sql).await;
    handle_migration_execution_result(ops, project, filename, checksum, result).await
}

async fn handle_migration_execution_result(
    ops: &Client,
    project: &str,
    filename: &str,
    checksum: &str,
    result: Result<i32, tokio_postgres::Error>,
) -> Result<bool, BoxError> {
    match result {
        Ok(dur) => {
            info!(project, file = filename, duration_ms = dur, "Applied");
            audit_migration_success(ops, project, filename, checksum, dur).await;
            Ok(true)
        }
        Err(e) => {
            let msg = e.to_string();
            error!(project, file = filename, error = msg, "Failed");
            audit_migration_failure(ops, project, filename, checksum, &msg).await;
            Err(e.into())
        }
    }
}

async fn apply_migration_file(
    db: &Client,
    ops: &Client,
    files: &dyn FileStore,
    project: &str,
    file: &crate::storage::MigrationFile,
    applied: &HashMap<String, String>,
) -> Result<bool, BoxError> {
    let (sql, checksum) = load_migration_sql_and_checksum(files, file).await?;
    let should_apply =
        ensure_migration_not_applied(ops, project, &file.filename, &checksum, applied).await?;
    if !should_apply {
        return Ok(false);
    }

    run_migration_file(db, ops, project, &file.filename, &checksum, &sql).await
}

pub async fn migrate(
    db: &Client,
    ops: &Client,
    files: &dyn FileStore,
    project: &str,
) -> Result<Response, BoxError> {
    db.batch_execute(LOCAL_TRACKING).await?;

    let migration_files = files.list_files(&format!("migrations/{project}/")).await?;
    info!(
        project,
        count = migration_files.len(),
        "Migration files found"
    );

    let applied = load_applied_migrations(db).await?;

    let mut count = 0i32;
    for file in &migration_files {
        if apply_migration_file(db, ops, files, project, file, &applied).await? {
            count += 1;
        }
    }

    info!(
        project,
        applied = count,
        total = migration_files.len(),
        "Migrate complete"
    );
    Ok(Response {
        operation: "migrate".into(),
        project: project.into(),
        applied: Some(count),
        ..Default::default()
    })
}

/// Record a migration as applied without executing it.
pub async fn noop(
    db: &Client,
    ops: &Client,
    files: &dyn FileStore,
    project: &str,
    target: &str,
    comment: &str,
) -> Result<Response, Box<dyn std::error::Error + Send + Sync>> {
    db.batch_execute(LOCAL_TRACKING).await?;

    let existing = db
        .query(
            "SELECT 1 FROM schema_migrations WHERE filename = $1",
            &[&target],
        )
        .await?;
    if !existing.is_empty() {
        info!(project, file = target, "Already recorded");
        return Ok(Response {
            operation: "noop".into(),
            project: project.into(),
            file: Some(target.into()),
            status: Some("already_recorded".into()),
            ..Default::default()
        });
    }

    let migration_files = files.list_files(&format!("migrations/{project}/")).await?;
    let file = migration_files
        .iter()
        .find(|f| f.filename == target)
        .ok_or_else(|| format!("Migration file not found: migrations/{project}/{target}"))?;

    let sql = files.read_file(&file.key).await?;
    let h = checksum(&sql);

    info!(project, file = target, comment, "Recording noop");
    db.execute(
        "INSERT INTO schema_migrations (filename, checksum, noop, comment, duration_ms) VALUES ($1, $2, TRUE, $3, 0)",
        &[&target, &h, &comment],
    )
    .await?;
    audit(
        ops,
        AuditEntry {
            project,
            operation: "noop",
            filename: Some(target),
            checksum: Some(&h),
            status: "success",
            error_message: None,
            duration_ms: Some(0),
            comment: Some(comment),
        },
    )
    .await;

    Ok(Response {
        operation: "noop".into(),
        project: project.into(),
        file: Some(target.into()),
        comment: Some(comment.into()),
        ..Default::default()
    })
}

/// Roll back migrations.
async fn load_applied_filenames_desc(db: &Client) -> Result<Vec<String>, BoxError> {
    let applied_rows = db
        .query(
            "SELECT filename FROM schema_migrations ORDER BY filename DESC",
            &[],
        )
        .await?;
    Ok(applied_rows.into_iter().map(|row| row.get(0)).collect())
}

async fn rollback_migration_file(
    db: &Client,
    ops: &Client,
    files: &dyn FileStore,
    project: &str,
    filename: &str,
    rollback_key: &str,
) -> Result<(), BoxError> {
    let sql = files.read_file(rollback_key).await?;
    info!(project, file = filename, "Rolling back");
    let start = std::time::Instant::now();

    db.batch_execute("BEGIN").await?;
    match db.batch_execute(&sql).await {
        Ok(()) => {
            db.execute(
                "DELETE FROM schema_migrations WHERE filename = $1",
                &[&filename],
            )
            .await?;
            db.batch_execute("COMMIT").await?;
            let dur = start.elapsed().as_millis() as i32;
            info!(project, file = filename, duration_ms = dur, "Rolled back");
            audit(
                ops,
                AuditEntry {
                    project,
                    operation: "rollback",
                    filename: Some(filename),
                    checksum: None,
                    status: "success",
                    error_message: None,
                    duration_ms: Some(dur),
                    comment: None,
                },
            )
            .await;
            Ok(())
        }
        Err(e) => {
            db.batch_execute("ROLLBACK").await.ok();
            let msg = e.to_string();
            audit(
                ops,
                AuditEntry {
                    project,
                    operation: "rollback",
                    filename: Some(filename),
                    checksum: None,
                    status: "error",
                    error_message: Some(&msg),
                    duration_ms: None,
                    comment: None,
                },
            )
            .await;
            Err(e.into())
        }
    }
}

pub async fn rollback(
    db: &Client,
    ops: &Client,
    files: &dyn FileStore,
    project: &str,
    target: Option<&str>,
) -> Result<Response, BoxError> {
    let applied_filenames = load_applied_filenames_desc(db).await?;
    if applied_filenames.is_empty() {
        info!(project, "Nothing to roll back");
        return Ok(Response {
            operation: "rollback".into(),
            project: project.into(),
            rolled_back: Some(0),
            ..Default::default()
        });
    }

    let rollback_files = files
        .list_files(&format!("migrations/{project}/rollback/"))
        .await?;
    let rollback_map: HashMap<String, String> = rollback_files
        .into_iter()
        .map(|f| (f.filename, f.key))
        .collect();

    let mut count = 0i32;
    for filename in &applied_filenames {
        if target.is_some_and(|t| filename.as_str() <= t) {
            break;
        }

        let rollback_key = rollback_map
            .get(filename)
            .ok_or_else(|| format!("No rollback file for {filename}"))?;

        rollback_migration_file(db, ops, files, project, filename, rollback_key).await?;
        count += 1;
    }

    Ok(Response {
        operation: "rollback".into(),
        project: project.into(),
        rolled_back: Some(count),
        ..Default::default()
    })
}

/// Run seed files.
async fn apply_seed_file(
    db: &Client,
    ops: &Client,
    files: &dyn FileStore,
    project: &str,
    file: &crate::storage::MigrationFile,
) -> Result<(), BoxError> {
    let sql = files.read_file(&file.key).await?;
    let h = checksum(&sql);
    info!(project, file = file.filename, "Seeding");
    let start = std::time::Instant::now();

    match db.batch_execute(&sql).await {
        Ok(()) => {
            let dur = start.elapsed().as_millis() as i32;
            info!(project, file = file.filename, duration_ms = dur, "Seeded");
            ops.execute(
                "INSERT INTO seed_runs (project, filename, checksum) VALUES ($1, $2, $3)",
                &[&project, &file.filename, &h],
            )
            .await
            .ok();
            audit(
                ops,
                AuditEntry {
                    project,
                    operation: "seed",
                    filename: Some(&file.filename),
                    checksum: Some(&h),
                    status: "success",
                    error_message: None,
                    duration_ms: Some(dur),
                    comment: None,
                },
            )
            .await;
            Ok(())
        }
        Err(e) => {
            let msg = e.to_string();
            audit(
                ops,
                AuditEntry {
                    project,
                    operation: "seed",
                    filename: Some(&file.filename),
                    checksum: Some(&h),
                    status: "error",
                    error_message: Some(&msg),
                    duration_ms: None,
                    comment: None,
                },
            )
            .await;
            Err(e.into())
        }
    }
}

pub async fn seed(
    db: &Client,
    ops: &Client,
    files: &dyn FileStore,
    project: &str,
) -> Result<Response, BoxError> {
    let seed_files = files
        .list_files(&format!("migrations/{project}/seed/"))
        .await?;
    if seed_files.is_empty() {
        info!(project, "No seed files");
        return Ok(Response {
            operation: "seed".into(),
            project: project.into(),
            applied: Some(0),
            ..Default::default()
        });
    }

    let mut count = 0i32;
    for file in &seed_files {
        apply_seed_file(db, ops, files, project, file).await?;
        count += 1;
    }

    Ok(Response {
        operation: "seed".into(),
        project: project.into(),
        applied: Some(count),
        ..Default::default()
    })
}
