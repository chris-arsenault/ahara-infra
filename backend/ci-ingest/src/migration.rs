use chrono::{DateTime, Utc};
use serde::Serialize;
use tokio_postgres::Client;

const BATCH_SIZE: i64 = 500;

#[derive(Debug)]
struct LegacyBuild {
    id: i32,
    repo: String,
    workflow: String,
    status: String,
    branch: String,
    commit_sha: String,
    run_id: String,
    run_url: Option<String>,
    duration_seconds: Option<i32>,
    lint_passed: Option<bool>,
    test_passed: Option<bool>,
    created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct LegacyMigrationSummary {
    pub source_rows: i64,
    pub inserted_rows: i64,
    pub verified_rows: i64,
    pub destination_rows: i64,
}

pub async fn migrate_legacy_builds(
    source: &mut Client,
    destination: &mut Client,
) -> Result<LegacyMigrationSummary, Box<dyn std::error::Error + Send + Sync>> {
    crate::db::init_schema(destination).await?;

    let source_tx = source.transaction().await?;
    source_tx
        .batch_execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        .await?;
    let source_rows: i64 = source_tx
        .query_one("SELECT COUNT(*) FROM ci_builds", &[])
        .await?
        .get(0);

    let mut last_id = 0_i32;
    let mut inserted_rows = 0_i64;
    let mut verified_rows = 0_i64;

    loop {
        let rows = source_tx
            .query(
                "SELECT id, repo, workflow, status, branch, commit_sha, run_id,
                        run_url, duration_seconds, lint_passed, test_passed, created_at
                 FROM ci_builds
                 WHERE id > $1
                 ORDER BY id
                 LIMIT $2",
                &[&last_id, &BATCH_SIZE],
            )
            .await?;
        if rows.is_empty() {
            break;
        }

        let builds = rows
            .into_iter()
            .map(|row| LegacyBuild {
                id: row.get(0),
                repo: row.get(1),
                workflow: row.get(2),
                status: row.get(3),
                branch: row.get(4),
                commit_sha: row.get(5),
                run_id: row.get(6),
                run_url: row.get(7),
                duration_seconds: row.get(8),
                lint_passed: row.get(9),
                test_passed: row.get(10),
                created_at: row.get(11),
            })
            .collect::<Vec<_>>();
        last_id = builds.last().expect("non-empty legacy batch").id;

        let destination_tx = destination.transaction().await?;
        for build in &builds {
            inserted_rows += destination_tx
                .execute(
                    "INSERT INTO ci_run (
                       repo, workflow, status, branch, commit_sha, run_id, run_url,
                       duration_seconds, lint_passed, test_passed, created_at, updated_at
                     )
                     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $11)
                     ON CONFLICT (run_id) DO NOTHING",
                    &[
                        &build.repo,
                        &build.workflow,
                        &build.status,
                        &build.branch,
                        &build.commit_sha,
                        &build.run_id,
                        &build.run_url,
                        &build.duration_seconds,
                        &build.lint_passed,
                        &build.test_passed,
                        &build.created_at,
                    ],
                )
                .await? as i64;
        }
        destination_tx.commit().await?;

        let run_ids = builds
            .iter()
            .map(|build| build.run_id.as_str())
            .collect::<Vec<_>>();
        let batch_verified: i64 = destination
            .query_one(
                "SELECT COUNT(*) FROM ci_run WHERE run_id = ANY($1)",
                &[&run_ids],
            )
            .await?
            .get(0);
        if batch_verified != builds.len() as i64 {
            return Err(format!(
                "Legacy CI migration parity failed for ids after {last_id}: expected {}, found {batch_verified}",
                builds.len()
            )
            .into());
        }
        verified_rows += batch_verified;
    }
    source_tx.commit().await?;

    if verified_rows != source_rows {
        return Err(format!(
            "Legacy CI migration parity failed: source has {source_rows} rows, destination verified {verified_rows}"
        )
        .into());
    }

    let destination_rows: i64 = destination
        .query_one("SELECT COUNT(*) FROM ci_run", &[])
        .await?
        .get(0);

    Ok(LegacyMigrationSummary {
        source_rows,
        inserted_rows,
        verified_rows,
        destination_rows,
    })
}
