use chrono::{DateTime, Utc};
use serde::Serialize;
use tokio_postgres::{Client, Transaction};

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

async fn insert_builds(
    destination: &Transaction<'_>,
    builds: &[LegacyBuild],
) -> Result<u64, tokio_postgres::Error> {
    let repos = builds
        .iter()
        .map(|build| build.repo.as_str())
        .collect::<Vec<_>>();
    let workflows = builds
        .iter()
        .map(|build| build.workflow.as_str())
        .collect::<Vec<_>>();
    let statuses = builds
        .iter()
        .map(|build| build.status.as_str())
        .collect::<Vec<_>>();
    let branches = builds
        .iter()
        .map(|build| build.branch.as_str())
        .collect::<Vec<_>>();
    let commit_shas = builds
        .iter()
        .map(|build| build.commit_sha.as_str())
        .collect::<Vec<_>>();
    let run_ids = builds
        .iter()
        .map(|build| build.run_id.as_str())
        .collect::<Vec<_>>();
    let run_urls = builds
        .iter()
        .map(|build| build.run_url.as_deref())
        .collect::<Vec<_>>();
    let duration_seconds = builds
        .iter()
        .map(|build| build.duration_seconds)
        .collect::<Vec<_>>();
    let lint_passed = builds
        .iter()
        .map(|build| build.lint_passed)
        .collect::<Vec<_>>();
    let test_passed = builds
        .iter()
        .map(|build| build.test_passed)
        .collect::<Vec<_>>();
    let created_at = builds
        .iter()
        .map(|build| build.created_at)
        .collect::<Vec<_>>();

    destination
        .execute(
            "INSERT INTO ci_run (
               repo, workflow, status, branch, commit_sha, run_id, run_url,
               duration_seconds, lint_passed, test_passed, created_at, updated_at
             )
             SELECT repo, workflow, status, branch, commit_sha, run_id, run_url,
                    duration_seconds, lint_passed, test_passed, created_at, created_at
             FROM UNNEST(
               $1::text[], $2::text[], $3::text[], $4::text[], $5::text[], $6::text[],
               $7::text[], $8::integer[], $9::boolean[], $10::boolean[], $11::timestamptz[]
             ) AS rows(
               repo, workflow, status, branch, commit_sha, run_id, run_url,
               duration_seconds, lint_passed, test_passed, created_at
             )
             ON CONFLICT (run_id) DO NOTHING",
            &[
                &repos,
                &workflows,
                &statuses,
                &branches,
                &commit_shas,
                &run_ids,
                &run_urls,
                &duration_seconds,
                &lint_passed,
                &test_passed,
                &created_at,
            ],
        )
        .await
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
        inserted_rows += insert_builds(&destination_tx, &builds).await? as i64;
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
