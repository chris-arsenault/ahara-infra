use std::collections::BTreeMap;
use std::fmt;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdoptionViolation {
    pub path: PathBuf,
    pub line: usize,
    pub message: String,
}

impl fmt::Display for AdoptionViolation {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "{}:{}: {}",
            self.path.display(),
            self.line,
            self.message
        )
    }
}

pub fn scan_paths(paths: &[PathBuf]) -> io::Result<Vec<AdoptionViolation>> {
    let mut scan = ScanState::default();
    for path in paths {
        scan_path(path, &mut scan)?;
    }
    scan.add_missing_operation_violations();
    Ok(scan.violations)
}

#[derive(Debug, Default)]
struct ScanState {
    violations: Vec<AdoptionViolation>,
    packages: BTreeMap<PathBuf, PackageTelemetry>,
}

impl ScanState {
    fn observe_wrapper(&mut self, path: &Path, line: usize) {
        let package = self.package_for(path);
        self.packages
            .entry(package)
            .or_default()
            .observe_wrapper(path, line);
    }

    fn observe_operation(&mut self, path: &Path) {
        let package = self.package_for(path);
        self.packages.entry(package).or_default().has_operation = true;
    }

    fn add_missing_operation_violations(&mut self) {
        for package in self.packages.values() {
            if package.requires_operation_span() {
                let (path, line) = package.wrapper.as_ref().expect("wrapper present");
                self.violations.push(violation(
                    path,
                    *line,
                    "Lambda crate uses Ahara telemetry run wrapper but declares no Operation span",
                ));
            }
        }
    }

    fn package_for(&self, path: &Path) -> PathBuf {
        package_root(path).unwrap_or_else(|| path.parent().unwrap_or(path).to_path_buf())
    }
}

#[derive(Debug, Default)]
struct PackageTelemetry {
    wrapper: Option<(PathBuf, usize)>,
    has_operation: bool,
}

impl PackageTelemetry {
    fn observe_wrapper(&mut self, path: &Path, line: usize) {
        if self.wrapper.is_none() {
            self.wrapper = Some((path.to_path_buf(), line));
        }
    }

    fn requires_operation_span(&self) -> bool {
        self.wrapper.is_some() && !self.has_operation
    }
}

fn scan_path(path: &Path, scan: &mut ScanState) -> io::Result<()> {
    if should_skip(path) {
        return Ok(());
    }
    if path.is_dir() {
        for entry in fs::read_dir(path)? {
            scan_path(&entry?.path(), scan)?;
        }
        return Ok(());
    }
    if path.extension().and_then(|value| value.to_str()) != Some("rs") {
        return Ok(());
    }
    scan_file(path, scan)
}

fn scan_file(path: &Path, scan: &mut ScanState) -> io::Result<()> {
    let content = fs::read_to_string(path)?;
    for (index, line) in content.lines().enumerate() {
        if line.contains("tracing_subscriber::fmt") {
            scan.violations.push(violation(
                path,
                index + 1,
                "use ahara_lambda_telemetry::init_lambda_logging instead of direct subscriber setup",
            ));
        }
        if has_direct_runtime_run(line) {
            scan.violations.push(violation(
                path,
                index + 1,
                "use ahara_lambda_telemetry run wrappers instead of direct Lambda runtime run",
            ));
        }
        if has_telemetry_run_wrapper(line) {
            scan.observe_wrapper(path, index + 1);
        }
        if has_operation_span(line) {
            scan.observe_operation(path);
        }
    }
    Ok(())
}

fn has_direct_runtime_run(line: &str) -> bool {
    line.contains("lambda_http::run")
        || line.contains("lambda_runtime::run")
        || imports_run_from("lambda_http", line)
        || imports_run_from("lambda_runtime", line)
}

fn imports_run_from(crate_name: &str, line: &str) -> bool {
    let Some(start) = line.find(&format!("use {crate_name}::{{")) else {
        return false;
    };
    let imports = &line[start..];
    imports
        .trim_end_matches(';')
        .split(['{', '}', ','])
        .any(|part| part.trim() == "run")
}

fn has_telemetry_run_wrapper(line: &str) -> bool {
    line.contains("run_http_lambda(") || line.contains("run_event_lambda(")
}

fn has_operation_span(line: &str) -> bool {
    line.contains("Operation::new(")
        || line.contains("observe_operation(")
        || line.contains("observe_operation_with_logger(")
}

fn package_root(path: &Path) -> Option<PathBuf> {
    let mut current = path.parent();
    while let Some(directory) = current {
        if directory.join("Cargo.toml").is_file() {
            return Some(directory.to_path_buf());
        }
        current = directory.parent();
    }
    None
}

fn violation(path: &Path, line: usize, message: &str) -> AdoptionViolation {
    AdoptionViolation {
        path: path.to_path_buf(),
        line,
        message: message.to_string(),
    }
}

fn should_skip(path: &Path) -> bool {
    path.components().any(|component| {
        let value = component.as_os_str().to_string_lossy();
        matches!(
            value.as_ref(),
            "target" | "target-clippy" | ".git" | "node_modules" | "tests" | "examples" | "benches"
        )
    })
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::scan_paths;

    #[test]
    fn scanner_flags_direct_lambda_runtime_setup() {
        let root = std::env::temp_dir().join(format!(
            "ahara-telemetry-test-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(root.join("src")).unwrap();
        fs::write(
            root.join("src/main.rs"),
            r#"
use lambda_http::{run, service_fn};

fn main() {
    tracing_subscriber::fmt().json().init();
    lambda_runtime::run(service_fn(handler));
}
"#,
        )
        .unwrap();

        let violations = scan_paths(&[root.clone()]).unwrap();

        assert_eq!(violations.len(), 3);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn scanner_flags_wrapped_lambda_without_operation_span() {
        let root = temp_root("missing-operation");
        write_crate_file(
            &root,
            "api",
            "src/main.rs",
            r#"
use lambda_http::service_fn;

async fn handler() {}

fn main() {
    ahara_lambda_telemetry::run_http_lambda(
        ahara_lambda_telemetry::TelemetryConfig::new("api"),
        service_fn(handler),
    );
}
"#,
        );

        let violations = scan_paths(&[root.clone()]).unwrap();

        assert_eq!(violations.len(), 1);
        assert!(violations[0].message.contains("declares no Operation span"));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn scanner_accepts_operation_span_declared_outside_entrypoint() {
        let root = temp_root("operation-in-module");
        write_crate_file(
            &root,
            "api",
            "src/main.rs",
            r#"
use lambda_http::service_fn;

mod routes;

async fn handler() {}

fn main() {
    ahara_lambda_telemetry::run_http_lambda(
        ahara_lambda_telemetry::TelemetryConfig::new("api"),
        service_fn(handler),
    );
}
"#,
        );
        fs::write(
            root.join("api/src/routes.rs"),
            r#"
async fn capture() -> Result<(), String> {
    ahara_lambda_telemetry::Operation::new(
        ahara_lambda_telemetry::TelemetryConfig::new("api"),
        "api.capture",
    )
    .observe(async { Ok(()) })
    .await
}
"#,
        )
        .unwrap();

        let violations = scan_paths(&[root.clone()]).unwrap();

        assert!(violations.is_empty());
        fs::remove_dir_all(root).unwrap();
    }

    fn temp_root(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "ahara-telemetry-{name}-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ))
    }

    fn write_crate_file(root: &Path, crate_name: &str, relative_path: &str, content: &str) {
        let crate_root = root.join(crate_name);
        fs::create_dir_all(crate_root.join("src")).unwrap();
        fs::write(
            crate_root.join("Cargo.toml"),
            format!(
                "[package]\nname = \"{crate_name}\"\nversion = \"0.1.0\"\nedition = \"2021\"\n"
            ),
        )
        .unwrap();
        fs::write(crate_root.join(relative_path), content).unwrap();
    }
}
