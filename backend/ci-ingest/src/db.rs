use serde::Deserialize;
use serde_json::Value;
use tokio_postgres::Client;

const MIGRATIONS: &[(&str, &str)] = &[(
    "001_engineering_quality.sql",
    include_str!("../migrations/001_engineering_quality.sql"),
)];

pub async fn init_schema(client: &Client) -> Result<(), tokio_postgres::Error> {
    client
        .query_one("SELECT pg_advisory_lock($1)", &[&8_104_202_026_i64])
        .await?;
    client
        .batch_execute(
            "CREATE TABLE IF NOT EXISTS ci_schema_migration (
               version TEXT PRIMARY KEY,
               applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
             )",
        )
        .await?;

    for (version, sql) in MIGRATIONS {
        let applied = client
            .query_opt(
                "SELECT 1 FROM ci_schema_migration WHERE version = $1",
                &[version],
            )
            .await?
            .is_some();
        if !applied {
            client.batch_execute("BEGIN").await?;
            if let Err(error) = client.batch_execute(sql).await {
                client.batch_execute("ROLLBACK").await?;
                return Err(error);
            }
            if let Err(error) = client
                .execute(
                    "INSERT INTO ci_schema_migration (version) VALUES ($1)",
                    &[version],
                )
                .await
            {
                client.batch_execute("ROLLBACK").await?;
                return Err(error);
            }
            client.batch_execute("COMMIT").await?;
        }
    }
    client
        .query_one("SELECT pg_advisory_unlock($1)", &[&8_104_202_026_i64])
        .await?;
    Ok(())
}

#[derive(Deserialize)]
pub struct BuildReport {
    pub repo: Option<String>,
    pub workflow: Option<String>,
    pub status: Option<String>,
    pub branch: Option<String>,
    pub commit_sha: Option<String>,
    pub run_id: Option<String>,
    pub run_url: Option<String>,
    pub event_name: Option<String>,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
    pub duration_seconds: Option<i32>,
    pub lint_passed: Option<bool>,
    pub test_passed: Option<bool>,
    pub tests_total: Option<i32>,
    pub tests_passed: Option<i32>,
    pub tests_failed: Option<i32>,
    pub tests_skipped: Option<i32>,
    pub coverage_lines_total: Option<i32>,
    pub coverage_lines_covered: Option<i32>,
    pub coverage_line_rate: Option<f64>,
}

#[derive(Deserialize)]
pub struct CheckReport {
    pub job_name: String,
    pub name: String,
    pub category: String,
    pub status: String,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
    pub duration_ms: Option<i32>,
}

#[derive(Deserialize)]
pub struct TestSuiteReport {
    pub framework: String,
    pub path: String,
    pub name: String,
    pub tests: i32,
    pub passed: i32,
    pub failures: i32,
    pub errors: i32,
    pub skipped: i32,
    pub duration_ms: Option<i32>,
}

#[derive(Deserialize)]
pub struct CoverageFileReport {
    pub path: String,
    pub lines_total: i32,
    pub lines_covered: i32,
    pub line_rate: Option<f64>,
    pub branches_total: Option<i32>,
    pub branches_covered: Option<i32>,
    pub branch_rate: Option<f64>,
}

#[derive(Deserialize)]
pub struct QualityScanReport {
    pub scan_id: String,
    pub run_id: String,
    pub repo: String,
    pub branch: String,
    pub commit_sha: String,
    pub qlty_version: String,
    pub analyzer_digest: String,
    pub config_digest: String,
    pub status: String,
    pub files: Option<i32>,
    pub functions: Option<i32>,
    pub code_lines: Option<i32>,
    pub complexity: Option<i32>,
    pub cyclomatic: Option<i32>,
    pub findings: Option<i32>,
    pub debt_minutes: Option<i32>,
    pub duplicated_lines: Option<i32>,
    pub started_at: Option<String>,
}

#[derive(Deserialize)]
pub struct QualityCompleteReport {
    pub scan_id: String,
    pub status: String,
    pub completed_at: Option<String>,
}

#[derive(Deserialize)]
pub struct QualityFileMetric {
    pub path: String,
    pub name: String,
    pub fully_qualified_name: String,
    pub language: String,
    pub files: i32,
    pub classes: i32,
    pub functions: i32,
    pub fields: i32,
    pub lines: i32,
    pub code_lines: i32,
    pub comment_lines: i32,
    pub blank_lines: i32,
    pub complexity: i32,
    pub cyclomatic: i32,
    pub lcom4: Option<i32>,
    pub duplicated_lines: i32,
    pub finding_count: i32,
    pub debt_minutes: i32,
}

#[derive(Deserialize)]
pub struct QualityFunctionMetric {
    pub metric_key: String,
    pub path: String,
    pub symbol: String,
    pub start_line: Option<i32>,
    pub language: String,
    pub lines: i32,
    pub code_lines: i32,
    pub complexity: i32,
    pub cyclomatic: i32,
    pub lcom4: Option<i32>,
}

#[derive(Deserialize)]
pub struct QualitySource {
    pub path: String,
    pub language: String,
    pub content: String,
    pub content_sha256: String,
}

#[derive(Deserialize)]
pub struct QualityFinding {
    pub fingerprint: String,
    pub path: String,
    pub start_line: Option<i32>,
    pub end_line: Option<i32>,
    pub start_byte: Option<i32>,
    pub end_byte: Option<i32>,
    pub tool: String,
    pub driver: String,
    pub rule_key: String,
    pub message: String,
    pub level: String,
    pub language: String,
    pub category: String,
    pub effort_minutes: Option<i32>,
    pub value: Option<i32>,
    pub value_delta: Option<i32>,
    #[serde(default = "empty_array")]
    pub other_locations: Value,
    #[serde(default = "empty_object")]
    pub properties: Value,
}

fn empty_array() -> Value {
    Value::Array(Vec::new())
}

fn empty_object() -> Value {
    Value::Object(Default::default())
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum BatchReport {
    Checks {
        run_id: String,
        items: Vec<CheckReport>,
    },
    TestSuites {
        run_id: String,
        items: Vec<TestSuiteReport>,
    },
    CoverageFiles {
        run_id: String,
        items: Vec<CoverageFileReport>,
    },
    QualityFiles {
        scan_id: String,
        items: Vec<QualityFileMetric>,
    },
    QualityFunctions {
        scan_id: String,
        items: Vec<QualityFunctionMetric>,
    },
    QualitySources {
        scan_id: String,
        items: Vec<QualitySource>,
    },
    QualityFindings {
        scan_id: String,
        items: Vec<QualityFinding>,
    },
}

impl BatchReport {
    pub fn len(&self) -> usize {
        match self {
            Self::Checks { items, .. } => items.len(),
            Self::TestSuites { items, .. } => items.len(),
            Self::CoverageFiles { items, .. } => items.len(),
            Self::QualityFiles { items, .. } => items.len(),
            Self::QualityFunctions { items, .. } => items.len(),
            Self::QualitySources { items, .. } => items.len(),
            Self::QualityFindings { items, .. } => items.len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn parent_id(&self) -> &str {
        match self {
            Self::Checks { run_id, .. }
            | Self::TestSuites { run_id, .. }
            | Self::CoverageFiles { run_id, .. } => run_id,
            Self::QualityFiles { scan_id, .. }
            | Self::QualityFunctions { scan_id, .. }
            | Self::QualitySources { scan_id, .. }
            | Self::QualityFindings { scan_id, .. } => scan_id,
        }
    }
}

pub fn validate_report(report: &BuildReport) -> Result<(), &'static str> {
    let fields = [
        &report.repo,
        &report.workflow,
        &report.status,
        &report.branch,
        &report.commit_sha,
        &report.run_id,
    ];
    if fields
        .iter()
        .any(|field| field.as_deref().unwrap_or("").is_empty())
    {
        return Err("Missing required fields");
    }
    Ok(())
}

pub fn validate_batch(batch: &BatchReport) -> Result<(), &'static str> {
    if batch.parent_id().is_empty() {
        return Err("Missing parent identifier");
    }
    if batch.is_empty() {
        return Err("Batch has no items");
    }
    if batch.len() > 250 {
        return Err("Batch exceeds 250 items");
    }
    if let BatchReport::QualitySources { items, .. } = batch {
        if items.iter().any(|item| {
            item.path.is_empty()
                || item.language.is_empty()
                || item.content_sha256.is_empty()
                || item.content.len() > 600_000
        }) {
            return Err("Invalid quality source item");
        }
    }
    Ok(())
}

pub async fn upsert_build(
    client: &Client,
    report: &BuildReport,
) -> Result<(), tokio_postgres::Error> {
    client
        .execute(
            "INSERT INTO ci_run (
               repo, workflow, status, branch, commit_sha, run_id, run_url,
               event_name, started_at, completed_at, duration_seconds,
               lint_passed, test_passed, tests_total, tests_passed, tests_failed,
               tests_skipped, coverage_lines_total, coverage_lines_covered,
               coverage_line_rate
             )
             VALUES (
               $1, $2, $3, $4, $5, $6, $7, $8,
               NULLIF($9, '')::timestamptz, NULLIF($10, '')::timestamptz,
               $11, $12, $13, $14, $15, $16, $17, $18, $19, $20
             )
             ON CONFLICT (run_id) DO UPDATE SET
               workflow = EXCLUDED.workflow,
               status = EXCLUDED.status,
               branch = EXCLUDED.branch,
               commit_sha = EXCLUDED.commit_sha,
               run_url = EXCLUDED.run_url,
               event_name = EXCLUDED.event_name,
               started_at = EXCLUDED.started_at,
               completed_at = EXCLUDED.completed_at,
               duration_seconds = EXCLUDED.duration_seconds,
               lint_passed = EXCLUDED.lint_passed,
               test_passed = EXCLUDED.test_passed,
               tests_total = EXCLUDED.tests_total,
               tests_passed = EXCLUDED.tests_passed,
               tests_failed = EXCLUDED.tests_failed,
               tests_skipped = EXCLUDED.tests_skipped,
               coverage_lines_total = EXCLUDED.coverage_lines_total,
               coverage_lines_covered = EXCLUDED.coverage_lines_covered,
               coverage_line_rate = EXCLUDED.coverage_line_rate,
               updated_at = NOW()",
            &[
                &report.repo.as_deref().unwrap_or(""),
                &report.workflow.as_deref().unwrap_or(""),
                &report.status.as_deref().unwrap_or(""),
                &report.branch.as_deref().unwrap_or(""),
                &report.commit_sha.as_deref().unwrap_or(""),
                &report.run_id.as_deref().unwrap_or(""),
                &report.run_url.as_deref(),
                &report.event_name.as_deref(),
                &report.started_at.as_deref().unwrap_or(""),
                &report.completed_at.as_deref().unwrap_or(""),
                &report.duration_seconds,
                &report.lint_passed,
                &report.test_passed,
                &report.tests_total,
                &report.tests_passed,
                &report.tests_failed,
                &report.tests_skipped,
                &report.coverage_lines_total,
                &report.coverage_lines_covered,
                &report.coverage_line_rate,
            ],
        )
        .await?;
    Ok(())
}

pub async fn start_quality_scan(
    client: &Client,
    scan: &QualityScanReport,
) -> Result<(), tokio_postgres::Error> {
    client
        .execute(
            "INSERT INTO quality_scan (
               scan_id, run_id, repo, branch, commit_sha, qlty_version,
               analyzer_digest, config_digest, status, files, functions,
               code_lines, complexity, cyclomatic, findings, debt_minutes,
               duplicated_lines, started_at
             )
             VALUES (
               $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
               $14, $15, $16, $17, COALESCE(NULLIF($18, '')::timestamptz, NOW())
             )
             ON CONFLICT (scan_id) DO UPDATE SET
               qlty_version = EXCLUDED.qlty_version,
               analyzer_digest = EXCLUDED.analyzer_digest,
               config_digest = EXCLUDED.config_digest,
               status = EXCLUDED.status,
               files = EXCLUDED.files,
               functions = EXCLUDED.functions,
               code_lines = EXCLUDED.code_lines,
               complexity = EXCLUDED.complexity,
               cyclomatic = EXCLUDED.cyclomatic,
               findings = EXCLUDED.findings,
               debt_minutes = EXCLUDED.debt_minutes,
               duplicated_lines = EXCLUDED.duplicated_lines,
               completed_at = NULL",
            &[
                &scan.scan_id,
                &scan.run_id,
                &scan.repo,
                &scan.branch,
                &scan.commit_sha,
                &scan.qlty_version,
                &scan.analyzer_digest,
                &scan.config_digest,
                &scan.status,
                &scan.files,
                &scan.functions,
                &scan.code_lines,
                &scan.complexity,
                &scan.cyclomatic,
                &scan.findings,
                &scan.debt_minutes,
                &scan.duplicated_lines,
                &scan.started_at.as_deref().unwrap_or(""),
            ],
        )
        .await?;
    Ok(())
}

pub async fn complete_quality_scan(
    client: &Client,
    report: &QualityCompleteReport,
) -> Result<u64, tokio_postgres::Error> {
    client
        .execute(
            "UPDATE quality_scan
             SET status = $2,
                 completed_at = COALESCE(NULLIF($3, '')::timestamptz, NOW())
             WHERE scan_id = $1",
            &[
                &report.scan_id,
                &report.status,
                &report.completed_at.as_deref().unwrap_or(""),
            ],
        )
        .await
}

pub async fn ingest_batch(
    client: &Client,
    batch: &BatchReport,
) -> Result<(), tokio_postgres::Error> {
    match batch {
        BatchReport::Checks { run_id, items } => {
            for item in items {
                client
                    .execute(
                        "INSERT INTO ci_check (
                           run_id, job_name, name, category, status,
                           started_at, completed_at, duration_ms
                         )
                         VALUES (
                           $1, $2, $3, $4, $5,
                           NULLIF($6, '')::timestamptz,
                           NULLIF($7, '')::timestamptz, $8
                         )
                         ON CONFLICT (run_id, job_name, name) DO UPDATE SET
                           category = EXCLUDED.category,
                           status = EXCLUDED.status,
                           started_at = EXCLUDED.started_at,
                           completed_at = EXCLUDED.completed_at,
                           duration_ms = EXCLUDED.duration_ms",
                        &[
                            run_id,
                            &item.job_name,
                            &item.name,
                            &item.category,
                            &item.status,
                            &item.started_at.as_deref().unwrap_or(""),
                            &item.completed_at.as_deref().unwrap_or(""),
                            &item.duration_ms,
                        ],
                    )
                    .await?;
            }
        }
        BatchReport::TestSuites { run_id, items } => {
            for item in items {
                client
                    .execute(
                        "INSERT INTO test_suite (
                           run_id, framework, path, name, tests, passed,
                           failures, errors, skipped, duration_ms
                         )
                         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
                         ON CONFLICT (run_id, framework, path, name) DO UPDATE SET
                           tests = EXCLUDED.tests,
                           passed = EXCLUDED.passed,
                           failures = EXCLUDED.failures,
                           errors = EXCLUDED.errors,
                           skipped = EXCLUDED.skipped,
                           duration_ms = EXCLUDED.duration_ms",
                        &[
                            run_id,
                            &item.framework,
                            &item.path,
                            &item.name,
                            &item.tests,
                            &item.passed,
                            &item.failures,
                            &item.errors,
                            &item.skipped,
                            &item.duration_ms,
                        ],
                    )
                    .await?;
            }
        }
        BatchReport::CoverageFiles { run_id, items } => {
            for item in items {
                client
                    .execute(
                        "INSERT INTO coverage_file (
                           run_id, path, lines_total, lines_covered, line_rate,
                           branches_total, branches_covered, branch_rate
                         )
                         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                         ON CONFLICT (run_id, path) DO UPDATE SET
                           lines_total = EXCLUDED.lines_total,
                           lines_covered = EXCLUDED.lines_covered,
                           line_rate = EXCLUDED.line_rate,
                           branches_total = EXCLUDED.branches_total,
                           branches_covered = EXCLUDED.branches_covered,
                           branch_rate = EXCLUDED.branch_rate",
                        &[
                            run_id,
                            &item.path,
                            &item.lines_total,
                            &item.lines_covered,
                            &item.line_rate,
                            &item.branches_total,
                            &item.branches_covered,
                            &item.branch_rate,
                        ],
                    )
                    .await?;
            }
        }
        BatchReport::QualityFiles { scan_id, items } => {
            for item in items {
                client
                    .execute(
                        "INSERT INTO quality_file_metric (
                           scan_id, path, name, fully_qualified_name, language,
                           files, classes, functions, fields, lines, code_lines,
                           comment_lines, blank_lines, complexity, cyclomatic,
                           lcom4, duplicated_lines, finding_count, debt_minutes
                         )
                         VALUES (
                           $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
                           $12, $13, $14, $15, $16, $17, $18, $19
                         )
                         ON CONFLICT (scan_id, path) DO UPDATE SET
                           name = EXCLUDED.name,
                           fully_qualified_name = EXCLUDED.fully_qualified_name,
                           language = EXCLUDED.language,
                           files = EXCLUDED.files,
                           classes = EXCLUDED.classes,
                           functions = EXCLUDED.functions,
                           fields = EXCLUDED.fields,
                           lines = EXCLUDED.lines,
                           code_lines = EXCLUDED.code_lines,
                           comment_lines = EXCLUDED.comment_lines,
                           blank_lines = EXCLUDED.blank_lines,
                           complexity = EXCLUDED.complexity,
                           cyclomatic = EXCLUDED.cyclomatic,
                           lcom4 = EXCLUDED.lcom4,
                           duplicated_lines = EXCLUDED.duplicated_lines,
                           finding_count = EXCLUDED.finding_count,
                           debt_minutes = EXCLUDED.debt_minutes",
                        &[
                            scan_id,
                            &item.path,
                            &item.name,
                            &item.fully_qualified_name,
                            &item.language,
                            &item.files,
                            &item.classes,
                            &item.functions,
                            &item.fields,
                            &item.lines,
                            &item.code_lines,
                            &item.comment_lines,
                            &item.blank_lines,
                            &item.complexity,
                            &item.cyclomatic,
                            &item.lcom4,
                            &item.duplicated_lines,
                            &item.finding_count,
                            &item.debt_minutes,
                        ],
                    )
                    .await?;
            }
        }
        BatchReport::QualityFunctions { scan_id, items } => {
            for item in items {
                client
                    .execute(
                        "INSERT INTO quality_function_metric (
                           scan_id, metric_key, path, symbol, start_line, language, lines,
                           code_lines, complexity, cyclomatic, lcom4
                         )
                         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
                         ON CONFLICT (scan_id, metric_key) DO UPDATE SET
                           path = EXCLUDED.path,
                           symbol = EXCLUDED.symbol,
                           start_line = EXCLUDED.start_line,
                           language = EXCLUDED.language,
                           lines = EXCLUDED.lines,
                           code_lines = EXCLUDED.code_lines,
                           complexity = EXCLUDED.complexity,
                           cyclomatic = EXCLUDED.cyclomatic,
                           lcom4 = EXCLUDED.lcom4",
                        &[
                            scan_id,
                            &item.metric_key,
                            &item.path,
                            &item.symbol,
                            &item.start_line,
                            &item.language,
                            &item.lines,
                            &item.code_lines,
                            &item.complexity,
                            &item.cyclomatic,
                            &item.lcom4,
                        ],
                    )
                    .await?;
            }
        }
        BatchReport::QualitySources { scan_id, items } => {
            for item in items {
                client
                    .execute(
                        "WITH scan AS (
                           SELECT repo, commit_sha
                           FROM quality_scan
                           WHERE scan_id = $1
                         ), source AS (
                           INSERT INTO quality_source (
                             repo, commit_sha, path, language, content, content_sha256
                           )
                           VALUES (
                             (SELECT repo FROM scan),
                             (SELECT commit_sha FROM scan),
                             $2, $3, $4, $5
                           )
                           ON CONFLICT (repo, commit_sha, path) DO UPDATE SET
                             language = EXCLUDED.language,
                             content = EXCLUDED.content,
                             content_sha256 = EXCLUDED.content_sha256
                           RETURNING repo, commit_sha, path
                         )
                         INSERT INTO quality_scan_source (scan_id, repo, commit_sha, path)
                         SELECT $1, repo, commit_sha, path
                         FROM source
                         ON CONFLICT (scan_id, path) DO NOTHING",
                        &[
                            scan_id,
                            &item.path,
                            &item.language,
                            &item.content,
                            &item.content_sha256,
                        ],
                    )
                    .await?;
            }
        }
        BatchReport::QualityFindings { scan_id, items } => {
            for item in items {
                client
                    .execute(
                        "INSERT INTO quality_finding (
                           scan_id, fingerprint, path, start_line, end_line,
                           start_byte, end_byte, tool, driver, rule_key, message,
                           level, language, category, effort_minutes, value,
                           value_delta, other_locations, properties
                         )
                         VALUES (
                           $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
                           $12, $13, $14, $15, $16, $17, $18, $19
                         )
                         ON CONFLICT (scan_id, fingerprint) DO UPDATE SET
                           path = EXCLUDED.path,
                           start_line = EXCLUDED.start_line,
                           end_line = EXCLUDED.end_line,
                           start_byte = EXCLUDED.start_byte,
                           end_byte = EXCLUDED.end_byte,
                           message = EXCLUDED.message,
                           level = EXCLUDED.level,
                           effort_minutes = EXCLUDED.effort_minutes,
                           value = EXCLUDED.value,
                           value_delta = EXCLUDED.value_delta,
                           other_locations = EXCLUDED.other_locations,
                           properties = EXCLUDED.properties",
                        &[
                            scan_id,
                            &item.fingerprint,
                            &item.path,
                            &item.start_line,
                            &item.end_line,
                            &item.start_byte,
                            &item.end_byte,
                            &item.tool,
                            &item.driver,
                            &item.rule_key,
                            &item.message,
                            &item.level,
                            &item.language,
                            &item.category,
                            &item.effort_minutes,
                            &item.value,
                            &item.value_delta,
                            &item.other_locations,
                            &item.properties,
                        ],
                    )
                    .await?;
            }
        }
    }
    Ok(())
}
