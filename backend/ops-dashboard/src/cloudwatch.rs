use std::collections::HashMap;
use std::time::Duration;

use aws_sdk_cloudwatchlogs::Client as LogsClient;
use lambda_http::Error;

use crate::query::OpsQuery;
use crate::AppState;

const QUERY_WAIT_ATTEMPTS: usize = 32;

pub(crate) type QueryRow = HashMap<String, String>;

#[derive(Debug)]
pub(crate) struct QueryResult {
    pub(crate) log_group_count: usize,
    pub(crate) rows: Vec<QueryRow>,
}

pub(crate) async fn execute_logs_query(
    state: &AppState,
    query: &OpsQuery,
    query_string: String,
) -> Result<QueryResult, Error> {
    let log_groups = discover_log_groups(state, query).await?;
    if log_groups.is_empty() {
        return Ok(QueryResult {
            log_group_count: 0,
            rows: Vec::new(),
        });
    }

    let started = state
        .logs
        .start_query()
        .set_log_group_names(Some(log_groups.clone()))
        .start_time(query.start_time())
        .end_time(query.end_time())
        .query_string(query_string)
        .send()
        .await?;
    let query_id = started
        .query_id()
        .ok_or_else(|| boxed_error("CloudWatch Logs Insights did not return a query id"))?
        .to_string();

    Ok(QueryResult {
        log_group_count: log_groups.len(),
        rows: wait_for_query(&state.logs, &query_id).await?,
    })
}

async fn discover_log_groups(state: &AppState, query: &OpsQuery) -> Result<Vec<String>, Error> {
    let mut groups = Vec::new();
    for prefix in state.config.log_group_prefixes(query) {
        collect_log_group_page(state, &mut groups, prefix).await?;
    }
    groups.sort();
    groups.dedup();
    groups.truncate(state.config.max_log_groups);
    Ok(groups)
}

async fn collect_log_group_page(
    state: &AppState,
    groups: &mut Vec<String>,
    prefix: String,
) -> Result<(), Error> {
    let mut next_token = None;
    while groups.len() < state.config.max_log_groups {
        let response = state
            .logs
            .describe_log_groups()
            .log_group_name_prefix(prefix.clone())
            .set_next_token(next_token)
            .send()
            .await?;
        groups.extend(
            response
                .log_groups()
                .iter()
                .filter_map(|group| group.log_group_name().map(str::to_string)),
        );
        next_token = response.next_token().map(str::to_string);
        if next_token.is_none() {
            break;
        }
    }
    Ok(())
}

async fn wait_for_query(client: &LogsClient, query_id: &str) -> Result<Vec<QueryRow>, Error> {
    for _ in 0..QUERY_WAIT_ATTEMPTS {
        let response = client.get_query_results().query_id(query_id).send().await?;
        match response.status().map(|status| status.as_str()) {
            Some("Complete") => return Ok(query_rows(response.results())),
            Some("Failed" | "Cancelled" | "Timeout") => {
                return Err(boxed_error(
                    "CloudWatch Logs Insights query did not complete",
                ))
            }
            _ => tokio::time::sleep(Duration::from_millis(250)).await,
        }
    }
    Err(boxed_error("CloudWatch Logs Insights query timed out"))
}

fn query_rows(results: &[Vec<aws_sdk_cloudwatchlogs::types::ResultField>]) -> Vec<QueryRow> {
    results
        .iter()
        .map(|fields| {
            fields
                .iter()
                .filter_map(|field| Some((field.field()?.to_string(), field.value()?.to_string())))
                .collect()
        })
        .collect()
}

fn boxed_error(message: impl Into<String>) -> Error {
    std::io::Error::other(message.into()).into()
}
