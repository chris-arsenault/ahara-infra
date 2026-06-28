pub mod adoption;
mod config;
mod event;
mod http;
mod logger;
mod operation;

pub use config::TelemetryConfig;
pub use event::{run_event_lambda, ObservedEventService};
pub use http::{run_http_lambda, ObservedHttpService};
pub use logger::{
    init_lambda_logging, HttpRequestErrorEvent, HttpRequestEvent, LambdaInvocationErrorEvent,
    LambdaInvocationEvent, OperationErrorEvent, OperationEvent, TelemetryLogger,
    TracingTelemetryLogger,
};
pub use operation::{observe_operation, observe_operation_with_logger, Operation};

pub mod prelude {
    pub use crate::{
        init_lambda_logging, observe_operation, run_event_lambda, run_http_lambda, Operation,
        TelemetryConfig,
    };
}
