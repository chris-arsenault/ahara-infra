use ci_ingest::db::{
    self, BatchReport, BuildReport, CheckReport, CoverageFileReport, QualityCompleteReport,
    QualityFileMetric, QualityFinding, QualityFunctionMetric, QualityScanReport, QualitySource,
    TestSuiteReport,
};
use ci_ingest::migration::migrate_legacy_builds;
use serde_json::json;
use testcontainers::runners::AsyncRunner;
use testcontainers_modules::postgres::Postgres;
use tokio_postgres::NoTls;

async fn setup() -> (
    tokio_postgres::Client,
    testcontainers::ContainerAsync<Postgres>,
) {
    let container = Postgres::default().start().await.unwrap();
    let host = container.get_host().await.unwrap();
    let port = container.get_host_port_ipv4(5432).await.unwrap();
    let connstr =
        format!("host={host} port={port} user=postgres password=postgres dbname=postgres");
    let (client, connection) = tokio_postgres::connect(&connstr, NoTls).await.unwrap();
    tokio::spawn(async move {
        connection.await.ok();
    });
    db::init_schema(&client).await.unwrap();
    (client, container)
}

fn sample_report(run_id: &str) -> BuildReport {
    BuildReport {
        repo: Some("chris-arsenault/test-repo".into()),
        workflow: Some("Deploy".into()),
        status: Some("success".into()),
        branch: Some("main".into()),
        commit_sha: Some("abc123".into()),
        run_id: Some(run_id.into()),
        run_url: Some("https://github.com/test/actions/runs/1".into()),
        event_name: Some("push".into()),
        started_at: Some("2026-08-10T12:00:00Z".into()),
        completed_at: Some("2026-08-10T12:00:42Z".into()),
        duration_seconds: Some(42),
        lint_passed: Some(true),
        test_passed: Some(true),
        tests_total: Some(12),
        tests_passed: Some(12),
        tests_failed: Some(0),
        tests_skipped: Some(0),
        coverage_lines_total: Some(100),
        coverage_lines_covered: Some(85),
        coverage_line_rate: Some(0.85),
    }
}

#[tokio::test]
async fn test_validate_report_ok() {
    let report = sample_report("run-1");
    assert!(db::validate_report(&report).is_ok());
}

#[tokio::test]
async fn test_validate_report_missing_repo() {
    let mut report = sample_report("run-1");
    report.repo = None;
    assert!(db::validate_report(&report).is_err());
}

#[tokio::test]
async fn test_validate_report_empty_status() {
    let mut report = sample_report("run-1");
    report.status = Some("".into());
    assert!(db::validate_report(&report).is_err());
}

#[tokio::test]
async fn test_upsert_builds() {
    let (client, _container) = setup().await;

    db::upsert_build(&client, &sample_report("run-100"))
        .await
        .unwrap();
    db::upsert_build(&client, &sample_report("run-101"))
        .await
        .unwrap();

    let rows = client
        .query("SELECT run_id FROM ci_run ORDER BY run_id", &[])
        .await
        .unwrap();
    let run_ids = rows
        .iter()
        .map(|row| row.get::<_, String>(0))
        .collect::<Vec<_>>();
    assert_eq!(run_ids, ["run-100", "run-101"]);
}

#[tokio::test]
async fn test_upsert_updates_on_conflict() {
    let (client, _container) = setup().await;

    let mut report = sample_report("run-200");
    report.status = Some("running".into());
    report.lint_passed = None;
    db::upsert_build(&client, &report).await.unwrap();

    report.status = Some("success".into());
    report.lint_passed = Some(true);
    db::upsert_build(&client, &report).await.unwrap();

    let row = client
        .query_one(
            "SELECT status, lint_passed, tests_total, coverage_line_rate
             FROM ci_run WHERE run_id = 'run-200'",
            &[],
        )
        .await
        .unwrap();
    assert_eq!(row.get::<_, String>(0), "success");
    assert!(row.get::<_, bool>(1));
    assert_eq!(row.get::<_, i32>(2), 12);
    assert_eq!(row.get::<_, f64>(3), 0.85);
}

#[tokio::test]
async fn test_structured_engineering_report() {
    let (client, _container) = setup().await;
    db::upsert_build(&client, &sample_report("run-500"))
        .await
        .unwrap();

    let batches = [
        BatchReport::Checks {
            run_id: "run-500".into(),
            items: vec![CheckReport {
                job_name: "ci".into(),
                name: "Test rust".into(),
                category: "test".into(),
                status: "success".into(),
                started_at: Some("2026-08-10T12:00:00Z".into()),
                completed_at: Some("2026-08-10T12:00:42Z".into()),
                duration_ms: Some(42_000),
            }],
        },
        BatchReport::TestSuites {
            run_id: "run-500".into(),
            items: vec![TestSuiteReport {
                framework: "vitest".into(),
                path: "frontend/coverage/junit.xml".into(),
                name: "frontend".into(),
                tests: 8,
                passed: 7,
                failures: 1,
                errors: 0,
                skipped: 0,
                duration_ms: Some(1200),
            }],
        },
        BatchReport::CoverageFiles {
            run_id: "run-500".into(),
            items: vec![CoverageFileReport {
                path: "frontend/src/example.ts".into(),
                lines_total: 10,
                lines_covered: 8,
                line_rate: Some(0.8),
                branches_total: Some(4),
                branches_covered: Some(3),
                branch_rate: Some(0.75),
            }],
        },
    ];
    for batch in &batches {
        assert!(db::validate_batch(batch).is_ok());
        db::ingest_batch(&client, batch).await.unwrap();
    }

    let scan = QualityScanReport {
        scan_id: "run-500:qlty".into(),
        run_id: "run-500".into(),
        repo: "chris-arsenault/test-repo".into(),
        branch: "main".into(),
        commit_sha: "abc123".into(),
        qlty_version: "0.641.0".into(),
        analyzer_digest: "sha256:qlty".into(),
        config_digest: "sha256:config".into(),
        status: "pending".into(),
        files: Some(1),
        functions: Some(1),
        code_lines: Some(20),
        complexity: Some(5),
        cyclomatic: Some(7),
        findings: Some(1),
        debt_minutes: Some(10),
        duplicated_lines: Some(4),
        started_at: Some("2026-08-10T12:00:00Z".into()),
    };
    db::start_quality_scan(&client, &scan).await.unwrap();

    let quality_batches = [
        BatchReport::QualityFiles {
            scan_id: scan.scan_id.clone(),
            items: vec![QualityFileMetric {
                path: "src/example.rs".into(),
                name: "example.rs".into(),
                fully_qualified_name: "src/example.rs".into(),
                language: "rust".into(),
                files: 1,
                classes: 0,
                functions: 1,
                fields: 0,
                lines: 24,
                code_lines: 20,
                comment_lines: 1,
                blank_lines: 3,
                complexity: 5,
                cyclomatic: 7,
                lcom4: Some(0),
                duplicated_lines: 4,
                finding_count: 1,
                debt_minutes: 10,
            }],
        },
        BatchReport::QualityFunctions {
            scan_id: scan.scan_id.clone(),
            items: vec![QualityFunctionMetric {
                metric_key: "function-1".into(),
                path: "src/example.rs".into(),
                symbol: "example".into(),
                start_line: None,
                language: "rust".into(),
                lines: 12,
                code_lines: 10,
                complexity: 5,
                cyclomatic: 7,
                lcom4: None,
            }],
        },
        BatchReport::QualitySources {
            scan_id: scan.scan_id.clone(),
            items: vec![QualitySource {
                path: "src/example.rs".into(),
                language: "rust".into(),
                content: "fn example() {}\n".into(),
                content_sha256: "sha256:example".into(),
            }],
        },
        BatchReport::QualityFindings {
            scan_id: scan.scan_id.clone(),
            items: vec![QualityFinding {
                fingerprint: "finding-1".into(),
                path: "src/example.rs".into(),
                start_line: Some(4),
                end_line: Some(8),
                start_byte: None,
                end_byte: None,
                tool: "qlty".into(),
                driver: "duplication".into(),
                rule_key: "similar-code".into(),
                message: "Similar code".into(),
                level: "medium".into(),
                language: "rust".into(),
                category: "duplication".into(),
                effort_minutes: Some(10),
                value: Some(4),
                value_delta: None,
                other_locations: json!([]),
                properties: json!({"structural_hash": "abc"}),
            }],
        },
    ];
    for batch in &quality_batches {
        db::ingest_batch(&client, batch).await.unwrap();
    }

    let updated = db::complete_quality_scan(
        &client,
        &QualityCompleteReport {
            scan_id: scan.scan_id,
            status: "complete".into(),
            completed_at: Some("2026-08-10T12:00:43Z".into()),
        },
    )
    .await
    .unwrap();
    assert_eq!(updated, 1);

    for table in [
        "ci_check",
        "test_suite",
        "coverage_file",
        "quality_file_metric",
        "quality_function_metric",
        "quality_source",
        "quality_scan_source",
        "quality_finding",
    ] {
        let count: i64 = client
            .query_one(&format!("SELECT COUNT(*) FROM {table}"), &[])
            .await
            .unwrap()
            .get(0);
        assert_eq!(count, 1, "{table}");
    }

    let source = client
        .query_one(
            "SELECT source.repo, source.commit_sha, source.path, source.content
             FROM quality_source source
             JOIN quality_scan_source scan_source
               ON scan_source.repo = source.repo
              AND scan_source.commit_sha = source.commit_sha
              AND scan_source.path = source.path
             WHERE scan_source.scan_id = 'run-500:qlty'",
            &[],
        )
        .await
        .unwrap();
    assert_eq!(source.get::<_, String>(0), "chris-arsenault/test-repo");
    assert_eq!(source.get::<_, String>(1), "abc123");
    assert_eq!(source.get::<_, String>(2), "src/example.rs");
    assert_eq!(source.get::<_, String>(3), "fn example() {}\n");
}

#[tokio::test]
async fn test_legacy_history_migration_is_idempotent_and_catches_late_rows() {
    let (mut source, container) = setup().await;
    let host = container.get_host().await.unwrap();
    let port = container.get_host_port_ipv4(5432).await.unwrap();
    let connstr =
        format!("host={host} port={port} user=postgres password=postgres dbname=postgres");
    let (mut destination, connection) = tokio_postgres::connect(&connstr, NoTls).await.unwrap();
    tokio::spawn(async move {
        connection.await.ok();
    });

    source
        .batch_execute(
            "CREATE TABLE ci_builds (
               id SERIAL PRIMARY KEY,
               repo TEXT NOT NULL,
               workflow TEXT NOT NULL,
               status TEXT NOT NULL,
               branch TEXT NOT NULL,
               commit_sha TEXT NOT NULL,
               run_id TEXT NOT NULL UNIQUE,
               run_url TEXT,
               duration_seconds INTEGER,
               lint_passed BOOLEAN,
               test_passed BOOLEAN,
               created_at TIMESTAMPTZ DEFAULT NOW()
             );
             INSERT INTO ci_builds (
               repo, workflow, status, branch, commit_sha, run_id, run_url,
               duration_seconds, lint_passed, test_passed, created_at
             ) VALUES
               ('chris-arsenault/one', 'CI', 'success', 'main', 'aaa', 'legacy-1',
                'https://github.com/one/actions/runs/1', 42, TRUE, TRUE,
                '2026-08-01T01:02:03Z'),
               ('chris-arsenault/two', 'CI/CD', 'failure', 'main', 'bbb', 'legacy-2',
                NULL, 18, FALSE, NULL, '2026-08-02T02:03:04Z');",
        )
        .await
        .unwrap();

    let first = migrate_legacy_builds(&mut source, &mut destination)
        .await
        .unwrap();
    assert_eq!(first.source_rows, 2);
    assert_eq!(first.inserted_rows, 2);
    assert_eq!(first.verified_rows, 2);
    assert_eq!(first.destination_rows, 2);

    let migrated = destination
        .query_one(
            "SELECT repo, status, duration_seconds, lint_passed, test_passed, created_at
             FROM ci_run WHERE run_id = 'legacy-2'",
            &[],
        )
        .await
        .unwrap();
    assert_eq!(migrated.get::<_, String>(0), "chris-arsenault/two");
    assert_eq!(migrated.get::<_, String>(1), "failure");
    assert_eq!(migrated.get::<_, Option<i32>>(2), Some(18));
    assert_eq!(migrated.get::<_, Option<bool>>(3), Some(false));
    assert_eq!(migrated.get::<_, Option<bool>>(4), None);
    assert_eq!(
        migrated.get::<_, chrono::DateTime<chrono::Utc>>(5),
        "2026-08-02T02:03:04Z"
            .parse::<chrono::DateTime<chrono::Utc>>()
            .unwrap()
    );

    destination
        .execute(
            "UPDATE ci_run SET event_name = 'push' WHERE run_id = 'legacy-2'",
            &[],
        )
        .await
        .unwrap();
    source
        .execute(
            "INSERT INTO ci_builds (
               repo, workflow, status, branch, commit_sha, run_id, duration_seconds,
               lint_passed, test_passed, created_at
             ) VALUES ('chris-arsenault/three', 'CI', 'success', 'main', 'ccc',
                       'legacy-3', 30, TRUE, TRUE, '2026-08-03T03:04:05Z')",
            &[],
        )
        .await
        .unwrap();

    let catch_up = migrate_legacy_builds(&mut source, &mut destination)
        .await
        .unwrap();
    assert_eq!(catch_up.source_rows, 3);
    assert_eq!(catch_up.inserted_rows, 1);
    assert_eq!(catch_up.verified_rows, 3);
    assert_eq!(catch_up.destination_rows, 3);

    let event_name: Option<String> = destination
        .query_one(
            "SELECT event_name FROM ci_run WHERE run_id = 'legacy-2'",
            &[],
        )
        .await
        .unwrap()
        .get(0);
    assert_eq!(event_name.as_deref(), Some("push"));
}
