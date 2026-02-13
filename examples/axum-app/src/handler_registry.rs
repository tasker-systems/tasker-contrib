//! Handler registry for the Axum example application.
//!
//! Bridges the plain function handlers in `handlers/` to the `StepHandler` trait
//! required by the tasker-worker dispatch system. Each function is wrapped in a
//! `FunctionHandler` that extracts context and dependency results from the
//! `TaskSequenceStep` and calls the underlying function.

use async_trait::async_trait;
use serde_json::Value;
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::Instant;

use tasker_shared::messaging::StepExecutionResult;
use tasker_shared::types::base::TaskSequenceStep;
use tasker_shared::TaskerResult;
use tasker_worker::worker::handlers::{StepHandler, StepHandlerRegistry};

use crate::handlers;

// ============================================================================
// FunctionHandler: wraps a closure as a StepHandler
// ============================================================================

type HandlerFn = Box<dyn Fn(&Value, &HashMap<String, Value>) -> Result<Value, String> + Send + Sync>;

struct FunctionHandler {
    handler_name: String,
    handler_fn: HandlerFn,
}

impl FunctionHandler {
    fn new(name: impl Into<String>, f: HandlerFn) -> Self {
        Self {
            handler_name: name.into(),
            handler_fn: f,
        }
    }
}

#[async_trait]
impl StepHandler for FunctionHandler {
    async fn call(&self, step: &TaskSequenceStep) -> TaskerResult<StepExecutionResult> {
        let start = Instant::now();

        // Extract task context (or empty object if missing)
        let context = step
            .task
            .task
            .context
            .clone()
            .unwrap_or_else(|| Value::Object(Default::default()));

        // Extract dependency results as HashMap<String, Value>
        let dep_results: HashMap<String, Value> = step
            .dependency_results
            .iter()
            .map(|(name, result)| (name.clone(), result.result.clone()))
            .collect();

        let elapsed_ms = start.elapsed().as_millis() as i64;

        match (self.handler_fn)(&context, &dep_results) {
            Ok(result) => Ok(StepExecutionResult::success(
                step.workflow_step.workflow_step_uuid,
                result,
                elapsed_ms,
                None,
            )),
            Err(err) => Ok(StepExecutionResult::failure(
                step.workflow_step.workflow_step_uuid,
                err,
                None,
                None,
                false,
                elapsed_ms,
                None,
            )),
        }
    }

    fn name(&self) -> &str {
        &self.handler_name
    }
}

// ============================================================================
// AxumHandlerRegistry: StepHandlerRegistry for all example handlers
// ============================================================================

pub struct AxumHandlerRegistry {
    handlers: RwLock<HashMap<String, Arc<dyn StepHandler>>>,
}

impl AxumHandlerRegistry {
    pub fn new() -> Self {
        let registry = Self {
            handlers: RwLock::new(HashMap::new()),
        };
        registry.register_all();
        registry
    }

    /// Number of registered handlers (for logging at startup).
    pub fn handler_count(&self) -> usize {
        self.handlers.read().expect("registry lock poisoned").len()
    }

    fn register_fn(&self, name: &str, f: HandlerFn) {
        let handler = Arc::new(FunctionHandler::new(name, f));
        self.handlers
            .write()
            .expect("registry lock poisoned")
            .insert(name.to_string(), handler);
    }

    fn register_all(&self) {
        // ================================================================
        // E-commerce Order Processing (5 handlers)
        // ================================================================
        self.register_fn(
            "ecommerce_validate_cart",
            Box::new(|ctx, _deps| handlers::ecommerce::validate_cart(ctx)),
        );
        self.register_fn(
            "ecommerce_process_payment",
            Box::new(|ctx, deps| handlers::ecommerce::process_payment(ctx, deps)),
        );
        self.register_fn(
            "ecommerce_update_inventory",
            Box::new(|_ctx, deps| handlers::ecommerce::update_inventory(deps)),
        );
        self.register_fn(
            "ecommerce_create_order",
            Box::new(|ctx, deps| handlers::ecommerce::create_order(ctx, deps)),
        );
        self.register_fn(
            "ecommerce_send_confirmation",
            Box::new(|ctx, deps| handlers::ecommerce::send_confirmation(ctx, deps)),
        );

        // ================================================================
        // Data Pipeline Analytics (8 handlers)
        // ================================================================
        self.register_fn(
            "data_pipeline_extract_sales",
            Box::new(|ctx, _deps| handlers::data_pipeline::extract_sales(ctx)),
        );
        self.register_fn(
            "data_pipeline_extract_inventory",
            Box::new(|ctx, _deps| handlers::data_pipeline::extract_inventory(ctx)),
        );
        self.register_fn(
            "data_pipeline_extract_customers",
            Box::new(|ctx, _deps| handlers::data_pipeline::extract_customers(ctx)),
        );
        self.register_fn(
            "data_pipeline_transform_sales",
            Box::new(|_ctx, deps| handlers::data_pipeline::transform_sales(deps)),
        );
        self.register_fn(
            "data_pipeline_transform_inventory",
            Box::new(|_ctx, deps| handlers::data_pipeline::transform_inventory(deps)),
        );
        self.register_fn(
            "data_pipeline_transform_customers",
            Box::new(|_ctx, deps| handlers::data_pipeline::transform_customers(deps)),
        );
        self.register_fn(
            "data_pipeline_aggregate_metrics",
            Box::new(|_ctx, deps| handlers::data_pipeline::aggregate_metrics(deps)),
        );
        self.register_fn(
            "data_pipeline_generate_insights",
            Box::new(|_ctx, deps| handlers::data_pipeline::generate_insights(deps)),
        );

        // ================================================================
        // Microservices User Registration (5 handlers)
        // ================================================================
        self.register_fn(
            "microservices_create_user_account",
            Box::new(|ctx, _deps| handlers::microservices::create_user_account(ctx)),
        );
        self.register_fn(
            "microservices_setup_billing_profile",
            Box::new(|ctx, deps| handlers::microservices::setup_billing_profile(ctx, deps)),
        );
        self.register_fn(
            "microservices_initialize_preferences",
            Box::new(|ctx, deps| handlers::microservices::initialize_preferences(ctx, deps)),
        );
        self.register_fn(
            "microservices_send_welcome_sequence",
            Box::new(|ctx, deps| handlers::microservices::send_welcome_sequence(ctx, deps)),
        );
        self.register_fn(
            "microservices_update_user_status",
            Box::new(|_ctx, deps| handlers::microservices::update_user_status(deps)),
        );

        // ================================================================
        // Customer Success - Process Refund (5 handlers)
        // ================================================================
        self.register_fn(
            "team_scaling_cs_validate_refund_request",
            Box::new(|ctx, _deps| handlers::customer_success::validate_refund_request(ctx)),
        );
        self.register_fn(
            "team_scaling_cs_check_refund_policy",
            Box::new(|ctx, deps| handlers::customer_success::check_refund_policy(ctx, deps)),
        );
        self.register_fn(
            "team_scaling_cs_get_manager_approval",
            Box::new(|_ctx, deps| handlers::customer_success::get_manager_approval(deps)),
        );
        self.register_fn(
            "team_scaling_cs_execute_refund_workflow",
            Box::new(|_ctx, deps| handlers::customer_success::execute_refund_workflow(deps)),
        );
        self.register_fn(
            "team_scaling_cs_update_ticket_status",
            Box::new(|ctx, deps| handlers::customer_success::update_ticket_status(ctx, deps)),
        );

        // ================================================================
        // Payments - Process Refund (4 handlers)
        // ================================================================
        self.register_fn(
            "team_scaling_payments_validate_eligibility",
            Box::new(|ctx, _deps| handlers::payments::validate_payment_eligibility(ctx)),
        );
        self.register_fn(
            "team_scaling_payments_process_gateway_refund",
            Box::new(|_ctx, deps| handlers::payments::process_gateway_refund(deps)),
        );
        self.register_fn(
            "team_scaling_payments_update_records",
            Box::new(|_ctx, deps| handlers::payments::update_payment_records(deps)),
        );
        self.register_fn(
            "team_scaling_payments_notify_customer",
            Box::new(|ctx, deps| handlers::payments::notify_customer(ctx, deps)),
        );
    }
}

#[async_trait]
impl StepHandlerRegistry for AxumHandlerRegistry {
    async fn get(&self, step: &TaskSequenceStep) -> Option<Arc<dyn StepHandler>> {
        let handlers = self.handlers.read().expect("registry lock poisoned");
        handlers
            .get(&step.step_definition.handler.callable)
            .cloned()
    }

    fn register(&self, name: &str, handler: Arc<dyn StepHandler>) {
        self.handlers
            .write()
            .expect("registry lock poisoned")
            .insert(name.to_string(), handler);
    }

    fn handler_available(&self, name: &str) -> bool {
        self.handlers
            .read()
            .expect("registry lock poisoned")
            .contains_key(name)
    }

    fn registered_handlers(&self) -> Vec<String> {
        self.handlers
            .read()
            .expect("registry lock poisoned")
            .keys()
            .cloned()
            .collect()
    }
}
