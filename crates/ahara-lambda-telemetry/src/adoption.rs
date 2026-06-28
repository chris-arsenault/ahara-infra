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
    let mut violations = Vec::new();
    for path in paths {
        scan_path(path, &mut violations)?;
    }
    Ok(violations)
}

fn scan_path(path: &Path, violations: &mut Vec<AdoptionViolation>) -> io::Result<()> {
    if should_skip(path) {
        return Ok(());
    }
    if path.is_dir() {
        for entry in fs::read_dir(path)? {
            scan_path(&entry?.path(), violations)?;
        }
        return Ok(());
    }
    if path.extension().and_then(|value| value.to_str()) != Some("rs") {
        return Ok(());
    }
    scan_file(path, violations)
}

fn scan_file(path: &Path, violations: &mut Vec<AdoptionViolation>) -> io::Result<()> {
    let content = fs::read_to_string(path)?;
    for (index, line) in content.lines().enumerate() {
        if line.contains("tracing_subscriber::fmt") {
            violations.push(violation(
                path,
                index + 1,
                "use ahara_lambda_telemetry::init_lambda_logging instead of direct subscriber setup",
            ));
        }
        if has_direct_runtime_run(line) {
            violations.push(violation(
                path,
                index + 1,
                "use ahara_lambda_telemetry run wrappers instead of direct Lambda runtime run",
            ));
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
            "target" | "target-clippy" | ".git" | "node_modules"
        )
    })
}

#[cfg(test)]
mod tests {
    use std::fs;
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
}
