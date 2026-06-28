use std::borrow::Cow;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TelemetryConfig {
    service_name: Cow<'static, str>,
    service_version: Cow<'static, str>,
    deployment_environment: Cow<'static, str>,
}

impl TelemetryConfig {
    pub fn new(service_name: impl Into<Cow<'static, str>>) -> Self {
        Self {
            service_name: service_name.into(),
            service_version: env_or_default("AWS_LAMBDA_FUNCTION_VERSION", "unknown"),
            deployment_environment: deployment_environment(),
        }
    }

    pub fn with_service_version(mut self, version: impl Into<Cow<'static, str>>) -> Self {
        self.service_version = version.into();
        self
    }

    pub fn with_deployment_environment(
        mut self,
        environment: impl Into<Cow<'static, str>>,
    ) -> Self {
        self.deployment_environment = environment.into();
        self
    }

    pub fn service_name(&self) -> &str {
        &self.service_name
    }

    pub fn service_version(&self) -> &str {
        &self.service_version
    }

    pub fn deployment_environment(&self) -> &str {
        &self.deployment_environment
    }
}

fn deployment_environment() -> Cow<'static, str> {
    for key in ["DEPLOYMENT_ENVIRONMENT", "APP_ENV", "ENVIRONMENT"] {
        if let Ok(value) = std::env::var(key) {
            if !value.trim().is_empty() {
                return Cow::Owned(value);
            }
        }
    }
    Cow::Borrowed("unknown")
}

fn env_or_default(key: &str, default: &'static str) -> Cow<'static, str> {
    std::env::var(key)
        .ok()
        .filter(|value| !value.trim().is_empty())
        .map(Cow::Owned)
        .unwrap_or(Cow::Borrowed(default))
}

#[cfg(test)]
mod tests {
    use super::TelemetryConfig;

    #[test]
    fn config_uses_service_name_and_defaults() {
        let config = TelemetryConfig::new("test-service");

        assert_eq!(config.service_name(), "test-service");
        assert!(!config.service_version().is_empty());
        assert!(!config.deployment_environment().is_empty());
    }
}
