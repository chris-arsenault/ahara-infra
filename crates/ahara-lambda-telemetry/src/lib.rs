pub mod adoption;
mod config;
mod event;
mod http;
mod logger;
mod metrics;
mod operation;
mod otel;
mod span_attrs;

pub use config::TelemetryConfig;
pub use event::{run_event_lambda, ObservedEventService};
pub use http::{run_http_lambda, ObservedHttpService};
pub use logger::{
    flush_lambda_telemetry, init_lambda_logging, HttpRequestErrorEvent, HttpRequestEvent,
    LambdaInvocationErrorEvent, LambdaInvocationEvent, OperationErrorEvent, OperationEvent,
    TelemetryLogger, TracingTelemetryLogger,
};
pub use operation::{
    observe_operation, observe_operation_with_logger, Operation, OperationDetails, OperationKind,
};

pub mod prelude {
    pub use crate::{
        init_lambda_logging, observe_operation, run_event_lambda, run_http_lambda, Operation,
        OperationKind, TelemetryConfig,
    };
}
