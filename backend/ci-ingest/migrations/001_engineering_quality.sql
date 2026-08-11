CREATE TABLE IF NOT EXISTS ci_run (
  id BIGSERIAL PRIMARY KEY,
  repo TEXT NOT NULL,
  workflow TEXT NOT NULL,
  status TEXT NOT NULL,
  branch TEXT NOT NULL,
  commit_sha TEXT NOT NULL,
  run_id TEXT NOT NULL UNIQUE,
  run_url TEXT,
  event_name TEXT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  duration_seconds INTEGER,
  lint_passed BOOLEAN,
  test_passed BOOLEAN,
  tests_total INTEGER,
  tests_passed INTEGER,
  tests_failed INTEGER,
  tests_skipped INTEGER,
  coverage_lines_total INTEGER,
  coverage_lines_covered INTEGER,
  coverage_line_rate DOUBLE PRECISION,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ci_run_repo_created
  ON ci_run (repo, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ci_run_status_created
  ON ci_run (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ci_run_commit
  ON ci_run (repo, commit_sha);

CREATE TABLE IF NOT EXISTS ci_check (
  id BIGSERIAL PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES ci_run(run_id) ON DELETE CASCADE,
  job_name TEXT NOT NULL,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  status TEXT NOT NULL,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  duration_ms INTEGER,
  UNIQUE (run_id, job_name, name)
);

CREATE INDEX IF NOT EXISTS idx_ci_check_run ON ci_check (run_id);

CREATE TABLE IF NOT EXISTS test_suite (
  id BIGSERIAL PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES ci_run(run_id) ON DELETE CASCADE,
  framework TEXT NOT NULL,
  path TEXT NOT NULL,
  name TEXT NOT NULL,
  tests INTEGER NOT NULL,
  passed INTEGER NOT NULL,
  failures INTEGER NOT NULL,
  errors INTEGER NOT NULL,
  skipped INTEGER NOT NULL,
  duration_ms INTEGER,
  UNIQUE (run_id, framework, path, name)
);

CREATE INDEX IF NOT EXISTS idx_test_suite_run ON test_suite (run_id);

CREATE TABLE IF NOT EXISTS coverage_file (
  id BIGSERIAL PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES ci_run(run_id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  lines_total INTEGER NOT NULL,
  lines_covered INTEGER NOT NULL,
  line_rate DOUBLE PRECISION,
  branches_total INTEGER,
  branches_covered INTEGER,
  branch_rate DOUBLE PRECISION,
  UNIQUE (run_id, path)
);

CREATE INDEX IF NOT EXISTS idx_coverage_file_run ON coverage_file (run_id);

CREATE TABLE IF NOT EXISTS quality_scan (
  scan_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES ci_run(run_id) ON DELETE CASCADE,
  repo TEXT NOT NULL,
  branch TEXT NOT NULL,
  commit_sha TEXT NOT NULL,
  qlty_version TEXT NOT NULL,
  analyzer_digest TEXT NOT NULL,
  config_digest TEXT NOT NULL,
  status TEXT NOT NULL,
  files INTEGER,
  functions INTEGER,
  code_lines INTEGER,
  complexity INTEGER,
  cyclomatic INTEGER,
  findings INTEGER,
  debt_minutes INTEGER,
  duplicated_lines INTEGER,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_quality_scan_repo_completed
  ON quality_scan (repo, completed_at DESC);
CREATE INDEX IF NOT EXISTS idx_quality_scan_commit
  ON quality_scan (repo, commit_sha);

CREATE TABLE IF NOT EXISTS quality_file_metric (
  scan_id TEXT NOT NULL REFERENCES quality_scan(scan_id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  name TEXT NOT NULL,
  fully_qualified_name TEXT NOT NULL,
  language TEXT NOT NULL,
  files INTEGER NOT NULL,
  classes INTEGER NOT NULL,
  functions INTEGER NOT NULL,
  fields INTEGER NOT NULL,
  lines INTEGER NOT NULL,
  code_lines INTEGER NOT NULL,
  comment_lines INTEGER NOT NULL,
  blank_lines INTEGER NOT NULL,
  complexity INTEGER NOT NULL,
  cyclomatic INTEGER NOT NULL,
  lcom4 INTEGER,
  duplicated_lines INTEGER NOT NULL DEFAULT 0,
  finding_count INTEGER NOT NULL DEFAULT 0,
  debt_minutes INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (scan_id, path)
);

CREATE INDEX IF NOT EXISTS idx_quality_file_hotspot
  ON quality_file_metric (scan_id, complexity DESC);

CREATE TABLE IF NOT EXISTS quality_function_metric (
  scan_id TEXT NOT NULL REFERENCES quality_scan(scan_id) ON DELETE CASCADE,
  metric_key TEXT NOT NULL,
  path TEXT NOT NULL,
  symbol TEXT NOT NULL,
  start_line INTEGER,
  language TEXT NOT NULL,
  lines INTEGER NOT NULL,
  code_lines INTEGER NOT NULL,
  complexity INTEGER NOT NULL,
  cyclomatic INTEGER NOT NULL,
  lcom4 INTEGER,
  PRIMARY KEY (scan_id, metric_key)
);

CREATE INDEX IF NOT EXISTS idx_quality_function_hotspot
  ON quality_function_metric (scan_id, complexity DESC);

CREATE TABLE IF NOT EXISTS quality_source (
  repo TEXT NOT NULL,
  commit_sha TEXT NOT NULL,
  path TEXT NOT NULL,
  language TEXT NOT NULL,
  content TEXT NOT NULL,
  content_sha256 TEXT NOT NULL,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (repo, commit_sha, path)
);

CREATE INDEX IF NOT EXISTS idx_quality_source_path
  ON quality_source (repo, commit_sha, path);

CREATE TABLE IF NOT EXISTS quality_scan_source (
  scan_id TEXT NOT NULL REFERENCES quality_scan(scan_id) ON DELETE CASCADE,
  repo TEXT NOT NULL,
  commit_sha TEXT NOT NULL,
  path TEXT NOT NULL,
  PRIMARY KEY (scan_id, path),
  FOREIGN KEY (repo, commit_sha, path)
    REFERENCES quality_source(repo, commit_sha, path)
);

CREATE TABLE IF NOT EXISTS quality_finding (
  scan_id TEXT NOT NULL REFERENCES quality_scan(scan_id) ON DELETE CASCADE,
  fingerprint TEXT NOT NULL,
  path TEXT NOT NULL,
  start_line INTEGER,
  end_line INTEGER,
  start_byte INTEGER,
  end_byte INTEGER,
  tool TEXT NOT NULL,
  driver TEXT NOT NULL,
  rule_key TEXT NOT NULL,
  message TEXT NOT NULL,
  level TEXT NOT NULL,
  language TEXT NOT NULL,
  category TEXT NOT NULL,
  effort_minutes INTEGER,
  value INTEGER,
  value_delta INTEGER,
  other_locations JSONB NOT NULL DEFAULT '[]'::jsonb,
  properties JSONB NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (scan_id, fingerprint)
);

CREATE INDEX IF NOT EXISTS idx_quality_finding_location
  ON quality_finding (scan_id, path, start_line);
CREATE INDEX IF NOT EXISTS idx_quality_finding_category
  ON quality_finding (scan_id, category, level);
