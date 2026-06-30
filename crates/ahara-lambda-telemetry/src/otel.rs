use std::env;

use opentelemetry::trace::TracerProvider as _;
use opentelemetry::{global, KeyValue};
use opentelemetry_otlp::{Protocol, WithExportConfig};
use opentelemetry_sdk::logs::SdkLoggerProvider;
use opentelemetry_sdk::metrics::SdkMeterProvider;
use opentelemetry_sdk::propagation::TraceContextPropagator;
use opentelemetry_sdk::trace::SdkTracerProvider;
use opentelemetry_sdk::Resource;

use crate::TelemetryConfig;

#[derive(Debug)]
pub(crate) struct OtelProviders {
    pub(crate) tracer_provider: Option<SdkTracerProvider>,
    pub(crate) meter_provider: Option<SdkMeterProvider>,
    pub(crate) logger_provider: Option<SdkLoggerProvider>,
}

impl OtelProviders {
    pub(crate) fn force_flush(&self) {
        if let Some(provider) = &self.tracer_provider {
            report_flush_result("traces", provider.force_flush());
        }
        if let Some(provider) = &self.meter_provider {
            report_flush_result("metrics", provider.force_flush());
        }
        if let Some(provider) = &self.logger_provider {
            report_flush_result("logs", provider.force_flush());
        }
    }
}

fn report_flush_result(signal: &str, result: opentelemetry_sdk::error::OTelSdkResult) {
    if let Err(err) = result {
        eprintln!("failed to flush OTEL {signal}: {err}");
    }
}

pub(crate) fn init_otel(config: &TelemetryConfig) -> OtelProviders {
    if sdk_disabled() {
        return OtelProviders {
            tracer_provider: None,
            meter_provider: None,
            logger_provider: None,
        };
    }
    global::set_text_map_propagator(TraceContextPropagator::new());
    OtelProviders {
        tracer_provider: init_traces(config),
        meter_provider: init_metrics(config),
        logger_provider: init_logs(config),
    }
}

pub(crate) fn tracer(
    provider: &SdkTracerProvider,
    config: &TelemetryConfig,
) -> opentelemetry_sdk::trace::Tracer {
    provider.tracer(config.service_name().to_string())
}

fn init_traces(config: &TelemetryConfig) -> Option<SdkTracerProvider> {
    if !signal_enabled("OTEL_TRACES_EXPORTER", "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT") {
        return None;
    }
    match opentelemetry_otlp::SpanExporter::builder()
        .with_http()
        .with_protocol(Protocol::HttpBinary)
        .build()
    {
        Ok(exporter) => {
            let provider = SdkTracerProvider::builder()
                .with_batch_exporter(exporter)
                .with_resource(resource(config))
                .build();
            global::set_tracer_provider(provider.clone());
            Some(provider)
        }
        Err(err) => {
            eprintln!("failed to initialize OTLP trace exporter: {err}");
            None
        }
    }
}

fn init_metrics(config: &TelemetryConfig) -> Option<SdkMeterProvider> {
    if !signal_enabled(
        "OTEL_METRICS_EXPORTER",
        "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT",
    ) {
        return None;
    }
    match opentelemetry_otlp::MetricExporter::builder()
        .with_http()
        .with_protocol(Protocol::HttpBinary)
        .build()
    {
        Ok(exporter) => {
            let provider = SdkMeterProvider::builder()
                .with_periodic_exporter(exporter)
                .with_resource(resource(config))
                .build();
            global::set_meter_provider(provider.clone());
            Some(provider)
        }
        Err(err) => {
            eprintln!("failed to initialize OTLP metric exporter: {err}");
            None
        }
    }
}

fn init_logs(config: &TelemetryConfig) -> Option<SdkLoggerProvider> {
    if !signal_enabled("OTEL_LOGS_EXPORTER", "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT") {
        return None;
    }
    match opentelemetry_otlp::LogExporter::builder()
        .with_http()
        .with_protocol(Protocol::HttpBinary)
        .build()
    {
        Ok(exporter) => Some(
            SdkLoggerProvider::builder()
                .with_batch_exporter(exporter)
                .with_resource(resource(config))
                .build(),
        ),
        Err(err) => {
            eprintln!("failed to initialize OTLP log exporter: {err}");
            None
        }
    }
}

fn resource(config: &TelemetryConfig) -> Resource {
    Resource::builder()
        .with_service_name(config.service_name().to_string())
        .with_attributes([
            KeyValue::new("service.version", config.service_version().to_string()),
            KeyValue::new(
                "deployment.environment.name",
                config.deployment_environment().to_string(),
            ),
            KeyValue::new("cloud.provider", "aws"),
            KeyValue::new("cloud.platform", "aws_lambda"),
        ])
        .build()
}

fn signal_enabled(exporter_key: &str, endpoint_key: &str) -> bool {
    match env::var(exporter_key).ok().map(|value| normalize(&value)) {
        Some(value) if value == "none" => false,
        Some(value) if value == "otlp" => true,
        Some(_) => endpoint_configured(endpoint_key),
        None => endpoint_configured(endpoint_key),
    }
}

fn endpoint_configured(signal_endpoint_key: &str) -> bool {
    env_present(signal_endpoint_key) || env_present("OTEL_EXPORTER_OTLP_ENDPOINT")
}

fn sdk_disabled() -> bool {
    env::var("OTEL_SDK_DISABLED")
        .ok()
        .map(|value| matches!(normalize(&value).as_str(), "true" | "1" | "yes"))
        .unwrap_or(false)
}

fn env_present(key: &str) -> bool {
    env::var(key)
        .ok()
        .map(|value| !value.trim().is_empty())
        .unwrap_or(false)
}

fn normalize(value: &str) -> String {
    value.trim().to_ascii_lowercase()
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use super::{endpoint_configured, sdk_disabled, signal_enabled};

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn exporter_requires_explicit_otlp_or_endpoint() {
        let _guard = ENV_LOCK.lock().unwrap();
        std::env::remove_var("OTEL_TRACES_EXPORTER");
        std::env::remove_var("OTEL_EXPORTER_OTLP_ENDPOINT");
        std::env::remove_var("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT");

        assert!(!signal_enabled(
            "OTEL_TRACES_EXPORTER",
            "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"
        ));
    }

    #[test]
    fn exporter_accepts_standard_otlp_settings() {
        let _guard = ENV_LOCK.lock().unwrap();
        std::env::set_var("OTEL_TRACES_EXPORTER", "otlp");
        assert!(signal_enabled(
            "OTEL_TRACES_EXPORTER",
            "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"
        ));
        std::env::set_var("OTEL_TRACES_EXPORTER", "none");
        assert!(!signal_enabled(
            "OTEL_TRACES_EXPORTER",
            "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"
        ));
        std::env::remove_var("OTEL_TRACES_EXPORTER");
    }

    #[test]
    fn endpoints_enable_exporters_without_custom_flags() {
        let _guard = ENV_LOCK.lock().unwrap();
        std::env::set_var("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318");
        assert!(endpoint_configured("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"));
        std::env::remove_var("OTEL_EXPORTER_OTLP_ENDPOINT");
    }

    #[test]
    fn sdk_disabled_uses_standard_env_var() {
        let _guard = ENV_LOCK.lock().unwrap();
        std::env::set_var("OTEL_SDK_DISABLED", "true");
        assert!(sdk_disabled());
        std::env::remove_var("OTEL_SDK_DISABLED");
    }
}
