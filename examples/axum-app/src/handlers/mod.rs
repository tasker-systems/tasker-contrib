//! Tasker step handler implementations for the Axum example application.
//!
//! Each module contains handlers for one of the 4 workflow patterns:
//! - `ecommerce`: E-commerce order processing (5 handlers)
//! - `data_pipeline`: Data pipeline analytics (8 handlers)
//! - `microservices`: Microservices user registration (5 handlers)
//! - `customer_success`: Customer success refund process (5 handlers)
//! - `payments`: Payments refund process (4 handlers)
//!
//! All handlers implement the `RustStepHandler` trait from tasker-worker and
//! follow the same patterns as the handlers in tasker-core's workers/rust crate.

pub mod customer_success;
pub mod data_pipeline;
pub mod ecommerce;
pub mod microservices;
pub mod payments;
