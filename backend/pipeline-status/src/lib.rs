use aws_sdk_dynamodb::{types::AttributeValue, Client};
use serde::Deserialize;
use std::collections::HashMap;

#[derive(Debug, Deserialize)]
pub struct Event {
    pub source: String,
    #[serde(rename = "detail-type")]
    pub detail_type: String,
    pub detail: Execution,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Execution {
    pub execution_arn: String,
    pub state_machine_arn: String,
    pub status: String,
    pub start_date: f64,
    pub stop_date: Option<f64>,
    pub error: Option<String>,
    #[serde(default)]
    pub redrive_count: u64,
}

impl Execution {
    pub fn is_terminal(&self) -> bool {
        matches!(
            self.status.as_str(),
            "SUCCEEDED" | "FAILED" | "TIMED_OUT" | "ABORTED"
        )
    }

    pub fn validate(&self) -> Result<(), String> {
        if !matches!(
            self.status.as_str(),
            "RUNNING" | "SUCCEEDED" | "FAILED" | "TIMED_OUT" | "ABORTED" | "PENDING_REDRIVE"
        ) {
            return Err(format!("Unsupported execution status: {}", self.status));
        }
        if !self.start_date.is_finite() || self.stop_date.is_some_and(|v| !v.is_finite()) {
            return Err("Invalid execution timestamp".into());
        }
        Ok(())
    }

    pub fn item(
        &self,
        registration: &HashMap<String, AttributeValue>,
    ) -> HashMap<String, AttributeValue> {
        let mut item = HashMap::from([
            (
                "execution_arn".into(),
                AttributeValue::S(self.execution_arn.clone()),
            ),
            (
                "workflow_arn".into(),
                AttributeValue::S(self.state_machine_arn.clone()),
            ),
            ("status".into(), AttributeValue::S(self.status.clone())),
            (
                "start_date".into(),
                AttributeValue::N(self.start_date.to_string()),
            ),
            ("terminal".into(), AttributeValue::Bool(self.is_terminal())),
            (
                "redrive_count".into(),
                AttributeValue::N(self.redrive_count.to_string()),
            ),
            (
                "event_order".into(),
                AttributeValue::N(self.stop_date.unwrap_or(self.start_date).to_string()),
            ),
        ]);
        for key in ["project", "pipeline"] {
            if let Some(value) = registration.get(key) {
                item.insert(key.into(), value.clone());
            }
        }
        if let Some(stop) = self.stop_date {
            item.insert("stop_date".into(), AttributeValue::N(stop.to_string()));
        }
        if let Some(error) = &self.error {
            item.insert(
                "error".into(),
                AttributeValue::S(error.chars().take(512).collect()),
            );
        }
        item
    }
}

/// A new redrive may reopen a terminal execution. Within one attempt, terminal
/// state wins over delayed RUNNING events and older terminal notifications.
pub const STATUS_CONDITION: &str = "attribute_not_exists(execution_arn) OR redrive_count < :attempt OR (redrive_count = :attempt AND (event_order < :order OR (event_order = :order AND terminal = :false AND :incoming_terminal = :true)) AND (terminal = :false OR :incoming_terminal = :true))";

pub async fn record(
    client: &Client,
    registry: &str,
    jobs: &str,
    event: Event,
) -> Result<bool, lambda_runtime::Error> {
    if event.source != "aws.states" || event.detail_type != "Step Functions Execution Status Change"
    {
        return Ok(false);
    }
    let execution = event.detail;
    execution.validate()?;
    let registration = client
        .get_item()
        .table_name(registry)
        .key(
            "workflow_arn",
            AttributeValue::S(execution.state_machine_arn.clone()),
        )
        .consistent_read(true)
        .send()
        .await?;
    let Some(registration) = registration.item else {
        return Ok(false);
    };
    let result = client
        .put_item()
        .table_name(jobs)
        .set_item(Some(execution.item(&registration)))
        .condition_expression(STATUS_CONDITION)
        .expression_attribute_values(
            ":attempt",
            AttributeValue::N(execution.redrive_count.to_string()),
        )
        .expression_attribute_values(
            ":order",
            AttributeValue::N(
                execution
                    .stop_date
                    .unwrap_or(execution.start_date)
                    .to_string(),
            ),
        )
        .expression_attribute_values(":false", AttributeValue::Bool(false))
        .expression_attribute_values(":true", AttributeValue::Bool(true))
        .expression_attribute_values(
            ":incoming_terminal",
            AttributeValue::Bool(execution.is_terminal()),
        )
        .send()
        .await;
    match result {
        Ok(_) => {
            let project = registration
                .get("project")
                .and_then(|v| v.as_s().ok())
                .map(String::as_str)
                .unwrap_or("unknown");
            let pipeline = registration
                .get("pipeline")
                .and_then(|v| v.as_s().ok())
                .map(String::as_str)
                .unwrap_or("unknown");
            tracing::info!(loki.attribute.labels = "event_name,project,pipeline,status", event_name = "pipeline.execution", project, pipeline, execution_arn = %execution.execution_arn, status = %execution.status, "Pipeline execution status");
            Ok(true)
        }
        Err(error)
            if error
                .as_service_error()
                .is_some_and(|e| e.is_conditional_check_failed_exception()) =>
        {
            Ok(false)
        }
        Err(error) => Err(error.into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_summary_without_private_workflow_payloads() {
        let event: Event = serde_json::from_value(serde_json::json!({"source":"aws.states", "detail-type":"Step Functions Execution Status Change", "detail":{"executionArn":"run", "stateMachineArn":"workflow", "status":"FAILED", "startDate":1.5, "stopDate":3.0, "error":"BadSource", "input":"private"}})).unwrap();
        let item = event.detail.item(&HashMap::new());
        assert_eq!(item["terminal"], AttributeValue::Bool(true));
        assert_eq!(item["event_order"], AttributeValue::N("3".into()));
        assert!(!item.contains_key("input"));
        assert!(event.detail.validate().is_ok());
    }

    #[test]
    fn rejects_unknown_status_and_invalid_timestamp() {
        let mut execution = Execution {
            execution_arn: "run".into(),
            state_machine_arn: "workflow".into(),
            status: "FAKE".into(),
            start_date: 1.0,
            stop_date: None,
            error: None,
            redrive_count: 0,
        };
        assert!(execution.validate().is_err());
        execution.status = "RUNNING".into();
        execution.start_date = f64::NAN;
        assert!(execution.validate().is_err());
    }
}
