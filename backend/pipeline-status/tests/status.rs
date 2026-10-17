use aws_sdk_dynamodb::{
    config::{Credentials, Region},
    types::{
        AttributeDefinition, AttributeValue, BillingMode, KeySchemaElement, KeyType,
        ScalarAttributeType,
    },
    Client,
};
use pipeline_status::{record, Event};
use testcontainers::{
    core::{IntoContainerPort, WaitFor},
    runners::AsyncRunner,
    GenericImage,
};

fn event(status: &str, attempt: u64) -> Event {
    serde_json::from_value(serde_json::json!({"source":"aws.states", "detail-type":"Step Functions Execution Status Change", "detail":{"executionArn":"run", "stateMachineArn":"workflow", "status":status, "startDate":1000.0, "stopDate": if status == "RUNNING" { serde_json::Value::Null } else { serde_json::json!(2000.0) }, "redriveCount":attempt}})).unwrap()
}

#[tokio::test]
async fn repeated_delayed_and_redriven_events_preserve_correct_status() {
    let container = GenericImage::new("amazon/dynamodb-local", "2.6.1")
        .with_exposed_port(8000.tcp())
        .with_wait_for(WaitFor::message_on_stdout("Initializing DynamoDB Local"))
        .start()
        .await
        .unwrap();
    let endpoint = format!(
        "http://127.0.0.1:{}",
        container.get_host_port_ipv4(8000).await.unwrap()
    );
    let client = Client::from_conf(
        aws_sdk_dynamodb::config::Builder::new()
            .behavior_version_latest()
            .region(Region::new("us-east-1"))
            .credentials_provider(Credentials::new("test", "test", None, None, "local-test"))
            .endpoint_url(&endpoint)
            .build(),
    );
    for _ in 0..50 {
        if reqwest::get(&endpoint).await.is_ok() {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }
    for (table, key) in [("registry", "workflow_arn"), ("jobs", "execution_arn")] {
        client
            .create_table()
            .table_name(table)
            .billing_mode(BillingMode::PayPerRequest)
            .attribute_definitions(
                AttributeDefinition::builder()
                    .attribute_name(key)
                    .attribute_type(ScalarAttributeType::S)
                    .build()
                    .unwrap(),
            )
            .key_schema(
                KeySchemaElement::builder()
                    .attribute_name(key)
                    .key_type(KeyType::Hash)
                    .build()
                    .unwrap(),
            )
            .send()
            .await
            .unwrap();
    }
    assert!(!record(&client, "registry", "jobs", event("RUNNING", 0))
        .await
        .unwrap());
    client
        .put_item()
        .table_name("registry")
        .item("workflow_arn", AttributeValue::S("workflow".into()))
        .item("project", AttributeValue::S("atlas".into()))
        .item("pipeline", AttributeValue::S("languages".into()))
        .send()
        .await
        .unwrap();
    assert!(record(&client, "registry", "jobs", event("SUCCEEDED", 0))
        .await
        .unwrap());
    assert!(!record(&client, "registry", "jobs", event("SUCCEEDED", 0))
        .await
        .unwrap());
    assert!(!record(&client, "registry", "jobs", event("RUNNING", 0))
        .await
        .unwrap());
    assert!(record(&client, "registry", "jobs", event("RUNNING", 1))
        .await
        .unwrap());
    assert!(!record(&client, "registry", "jobs", event("FAILED", 0))
        .await
        .unwrap());
    assert!(record(&client, "registry", "jobs", event("SUCCEEDED", 1))
        .await
        .unwrap());
    let summary = client
        .get_item()
        .table_name("jobs")
        .key("execution_arn", AttributeValue::S("run".into()))
        .send()
        .await
        .unwrap()
        .item
        .unwrap();
    assert_eq!(summary["status"], AttributeValue::S("SUCCEEDED".into()));
    assert_eq!(summary["project"], AttributeValue::S("atlas".into()));
}
