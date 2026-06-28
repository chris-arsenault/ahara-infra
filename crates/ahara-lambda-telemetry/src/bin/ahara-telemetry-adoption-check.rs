use std::path::PathBuf;

fn main() -> std::io::Result<()> {
    let paths = std::env::args_os()
        .skip(1)
        .map(PathBuf::from)
        .collect::<Vec<_>>();
    let paths = if paths.is_empty() {
        vec![std::env::current_dir()?]
    } else {
        paths
    };
    let violations = ahara_lambda_telemetry::adoption::scan_paths(&paths)?;
    if violations.is_empty() {
        return Ok(());
    }

    eprintln!("Ahara Lambda telemetry adoption violations:");
    for violation in violations {
        eprintln!("{violation}");
    }
    std::process::exit(1);
}
