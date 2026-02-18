//! # Integration Tests
//!
//! These tests boot an in-process Axum server on a random port and send
//! HTTP requests to it via reqwest. No external `cargo run` is needed.
//!
//! The full infrastructure stack (PostgreSQL, Tasker Orchestration) must
//! still be running for task creation and completion verification.
//!
//! ## Running Tests
//!
//! ```bash
//! # 1. Start shared infrastructure
//! cd examples/ && docker compose up -d
//!
//! # 2. Run all tests (including completion verification)
//! cd examples/axum-app && cargo nextest run
//! ```

#[cfg(test)]
mod tests {
    use serde_json::json;
    use std::sync::{Arc, OnceLock};

    static TEST_SERVER_URL: OnceLock<String> = OnceLock::new();

    /// Boot the in-process test server once in a background thread, returning the base URL.
    ///
    /// Uses a dedicated tokio runtime on a background thread so it doesn't
    /// conflict with #[tokio::test]'s per-test runtime.
    ///
    /// The Tasker worker is bootstrapped so that templates are registered
    /// with orchestration and step handlers can execute.
    fn base_url() -> &'static str {
        TEST_SERVER_URL.get_or_init(|| {
            dotenvy::dotenv().ok();

            let (tx, rx) = std::sync::mpsc::channel();

            std::thread::spawn(move || {
                // Use multi_thread runtime: the Tasker worker spawns background
                // tasks (polling, event handling) that need concurrent execution.
                let rt = tokio::runtime::Builder::new_multi_thread()
                    .enable_all()
                    .build()
                    .expect("Failed to build tokio runtime for test server");

                rt.block_on(async {
                    let db_url = example_axum_app::db::pool_from_env();
                    let pool = sqlx::postgres::PgPoolOptions::new()
                        .max_connections(5)
                        .connect(&db_url)
                        .await
                        .expect("Failed to connect to app database");

                    sqlx::migrate!("./migrations")
                        .run(&pool)
                        .await
                        .expect("Failed to run migrations");

                    // Bootstrap the Tasker worker: register templates with
                    // orchestration and start the handler dispatch pipeline.
                    {
                        use tasker_worker::worker::handlers::{
                            HandlerDispatchConfig, HandlerDispatchService, NoOpCallback,
                        };

                        let mut worker_handle = tasker_worker::WorkerBootstrap::bootstrap()
                            .await
                            .expect("Failed to bootstrap Tasker worker");

                        let registry =
                            Arc::new(example_axum_app::handler_registry::AxumHandlerRegistry::new());

                        if let Some(dispatch_handles) = worker_handle.take_dispatch_handles() {
                            let dispatch_config = HandlerDispatchConfig::default();
                            let (dispatch_service, _capacity_checker) =
                                HandlerDispatchService::with_callback(
                                    dispatch_handles.dispatch_receiver,
                                    dispatch_handles.completion_sender,
                                    registry,
                                    dispatch_config,
                                    Arc::new(NoOpCallback),
                                );

                            tokio::spawn(async move {
                                dispatch_service.run().await;
                            });
                        }

                        eprintln!("Tasker worker bootstrapped");
                    }

                    let app = example_axum_app::create_app(pool);

                    // Bind to port 0 for OS-assigned random port
                    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
                        .await
                        .expect("Failed to bind test listener");

                    let addr = listener.local_addr().expect("Failed to get local address");
                    let url = format!("http://127.0.0.1:{}", addr.port());

                    // Signal the URL back to the main thread
                    tx.send(url).expect("Failed to send test server URL");

                    // Run the server until the process exits
                    axum::serve(listener, app)
                        .await
                        .expect("Test server failed");
                });
            });

            rx.recv().expect("Failed to receive test server URL")
        })
    }

    fn orchestration_url() -> String {
        std::env::var("ORCHESTRATION_URL").unwrap_or_else(|_| "http://localhost:8080".to_string())
    }

    fn api_key() -> String {
        std::env::var("TASKER_API_KEY")
            .unwrap_or_else(|_| "test-api-key-full-access".to_string())
    }

    /// Terminal statuses that indicate a task is definitively done.
    const TERMINAL_STATUSES: &[&str] = &["complete", "error", "cancelled"];

    /// Failure statuses that may still transition (grace period before accepting).
    const FAILURE_STATUSES: &[&str] = &["blocked_by_failures"];

    /// Grace period: once a failure status is first seen, keep polling for this
    /// long before accepting it as final. This allows the orchestrator time to
    /// transition tasks out of transient blocked states.
    const FAILURE_GRACE_PERIOD: std::time::Duration = std::time::Duration::from_secs(10);

    /// Poll the orchestration API until the task reaches a terminal status.
    ///
    /// When `blocked_by_failures` is observed, a 10-second grace period begins.
    /// Polling continues during the grace period. If the status changes to a
    /// non-failure status, the timer resets. The task value is returned once:
    /// - A terminal status (`complete`, `error`, `cancelled`) is reached, OR
    /// - The grace period elapses while still in a failure status.
    async fn wait_for_task_completion(
        client: &reqwest::Client,
        task_uuid: &str,
    ) -> serde_json::Value {
        let url = format!("{}/v1/tasks/{}", orchestration_url(), task_uuid);
        let timeout = std::time::Duration::from_secs(60);
        let poll_interval = std::time::Duration::from_secs(1);
        let deadline = std::time::Instant::now() + timeout;

        // Track when we first observed a failure status (for grace period).
        let mut failure_first_seen: Option<std::time::Instant> = None;

        loop {
            let res = client
                .get(&url)
                .header("X-API-Key", api_key())
                .send()
                .await
                .expect("Failed to poll task");

            assert_eq!(res.status(), 200, "Expected 200 from orchestration API");

            let task: serde_json::Value = res.json().await.expect("Failed to parse task");
            let status = task["status"].as_str().unwrap_or("");

            // Immediate return for definitive terminal statuses.
            if TERMINAL_STATUSES.contains(&status) {
                return task;
            }

            // Grace period logic for failure statuses (e.g. blocked_by_failures).
            if FAILURE_STATUSES.contains(&status) {
                let first_seen = *failure_first_seen.get_or_insert_with(std::time::Instant::now);
                if first_seen.elapsed() >= FAILURE_GRACE_PERIOD {
                    // Grace period elapsed; accept the failure status as final.
                    return task;
                }
            } else {
                // Status is neither terminal nor failure; reset the timer.
                failure_first_seen = None;
            }

            assert!(
                std::time::Instant::now() < deadline,
                "Task {} did not complete within {}s. Last status: {}, completion: {}%",
                task_uuid,
                timeout.as_secs(),
                status,
                task["completion_percentage"]
            );

            tokio::time::sleep(poll_interval).await;
        }
    }

    #[tokio::test]
    async fn test_create_order() {
        let client = reqwest::Client::new();
        let res = client
            .post(format!("{}/orders", base_url()))
            .json(&json!({
                "customer_email": "test@example.com",
                "cart_items": [
                    {"sku": "1", "name": "Widget A", "quantity": 2, "unit_price": 29.99},
                    {"sku": "2", "name": "Widget B", "quantity": 1, "unit_price": 49.99}
                ],
                "payment_token": "tok_test_success",
                "shipping_address": {
                    "street": "123 Main St",
                    "city": "Anytown",
                    "state": "CA",
                    "zip": "90210",
                    "country": "US"
                }
            }))
            .send()
            .await
            .expect("Failed to send request");

        assert_eq!(res.status(), 201, "Expected 201 Created");

        let body: serde_json::Value = res.json().await.expect("Failed to parse response");
        assert!(body["data"]["id"].is_number(), "Response should contain order ID");
        assert_eq!(
            body["data"]["customer_email"].as_str().unwrap(),
            "test@example.com"
        );
        assert!(
            body["data"]["status"].as_str().unwrap() == "processing"
                || body["data"]["status"].as_str().unwrap() == "pending",
            "Status should be processing or pending"
        );
    }

    #[tokio::test]
    async fn test_create_order_async() {
        let client = reqwest::Client::new();
        let res = client
            .post(format!("{}/orders/async", base_url()))
            .json(&json!({
                "customer_email": "async-test@example.com",
                "cart_items": [
                    {"sku": "A1", "name": "Async Widget", "quantity": 1, "unit_price": 24.99}
                ],
                "payment_token": "tok_test_async",
                "shipping_address": {
                    "street": "2 Async Ave",
                    "city": "Testville",
                    "state": "OR",
                    "zip": "97201",
                    "country": "US"
                }
            }))
            .send()
            .await
            .expect("Failed to send request");

        assert_eq!(res.status(), 202, "Expected 202 Accepted");

        let body: serde_json::Value = res.json().await.expect("Failed to parse response");
        assert!(body["data"]["id"].is_number(), "Response should contain order ID");
        assert_eq!(body["data"]["status"].as_str().unwrap(), "queued");
    }

    #[tokio::test]
    async fn test_get_order_not_found() {
        let client = reqwest::Client::new();
        let res = client
            .get(format!("{}/orders/99999", base_url()))
            .send()
            .await
            .expect("Failed to send request");

        assert_eq!(res.status(), 404, "Expected 404 Not Found");
    }

    #[tokio::test]
    async fn test_create_analytics_job() {
        let client = reqwest::Client::new();
        let res = client
            .post(format!("{}/analytics", base_url()))
            .json(&json!({
                "job_name": "monthly_report_q4",
                "sources": ["sales", "inventory", "customers"],
                "date_range": {
                    "start_date": "2025-10-01",
                    "end_date": "2025-12-31"
                }
            }))
            .send()
            .await
            .expect("Failed to send request");

        assert_eq!(res.status(), 201, "Expected 201 Created");

        let body: serde_json::Value = res.json().await.expect("Failed to parse response");
        assert!(body["data"]["id"].is_number(), "Response should contain job ID");
        assert_eq!(
            body["data"]["job_name"].as_str().unwrap(),
            "monthly_report_q4"
        );
    }

    #[tokio::test]
    async fn test_create_user_registration() {
        let client = reqwest::Client::new();
        let res = client
            .post(format!("{}/services/register", base_url()))
            .json(&json!({
                "user_email": "newuser@example.com",
                "user_name": "New User",
                "plan": "pro"
            }))
            .send()
            .await
            .expect("Failed to send request");

        assert_eq!(res.status(), 201, "Expected 201 Created");

        let body: serde_json::Value = res.json().await.expect("Failed to parse response");
        assert!(
            body["data"]["id"].is_number(),
            "Response should contain service request ID"
        );
        assert_eq!(
            body["data"]["user_email"].as_str().unwrap(),
            "newuser@example.com"
        );
    }

    // -----------------------------------------------------------------------
    // Task Completion Verification
    //
    // These tests verify the full infrastructure loop: task creation, step
    // dispatch, handler execution, and result processing. All tasks must
    // reach "complete" status with every step in "complete" state.
    // -----------------------------------------------------------------------

    #[tokio::test]
    async fn test_ecommerce_order_dispatches_and_processes() {
        let client = reqwest::Client::new();
        let res = client
            .post(format!("{}/orders", base_url()))
            .json(&json!({
                "customer_email": "completion-test@example.com",
                "cart_items": [
                    {"sku": "C1", "name": "Completion Widget", "quantity": 1, "unit_price": 19.99}
                ],
                "payment_token": "tok_test_completion",
                "shipping_address": {
                    "street": "1 Test Ln",
                    "city": "Testville",
                    "state": "OR",
                    "zip": "97201",
                    "country": "US"
                }
            }))
            .send()
            .await
            .expect("Failed to send request");

        assert_eq!(res.status(), 201);
        let body: serde_json::Value = res.json().await.unwrap();
        let task_uuid = body["data"]["task_uuid"]
            .as_str()
            .expect("Expected task_uuid in response");

        let task = wait_for_task_completion(&client, task_uuid).await;

        // Task must fully complete (all steps successful)
        let status = task["status"].as_str().unwrap();
        assert_eq!(status, "complete", "Expected task to complete, got: {}", status);
        assert_eq!(task["total_steps"].as_i64().unwrap(), 5);

        // All steps must have reached "complete" state
        let steps = task["steps"].as_array().expect("Expected steps array");
        assert_eq!(steps.len(), 5);
        let completed = steps
            .iter()
            .filter(|s| s["current_state"].as_str() == Some("complete"))
            .count();
        assert_eq!(completed, 5, "Expected all 5 steps to complete, got {}", completed);

        // Handler dispatch works: first step was attempted
        let validate_step = steps
            .iter()
            .find(|s| s["name"].as_str() == Some("validate_cart"))
            .expect("Expected validate_cart step");
        assert!(validate_step["attempts"].as_i64().unwrap() >= 1);

        println!("  E-commerce task (sync): {} ({}/5 steps complete)", status, completed);
    }

    #[tokio::test]
    async fn test_ecommerce_order_async_dispatches_and_processes() {
        let client = reqwest::Client::new();
        let res = client
            .post(format!("{}/orders/async", base_url()))
            .json(&json!({
                "customer_email": "async-completion@example.com",
                "cart_items": [
                    {"sku": "A1", "name": "Async Widget", "quantity": 1, "unit_price": 24.99}
                ],
                "payment_token": "tok_test_async",
                "shipping_address": {
                    "street": "2 Async Ave",
                    "city": "Testville",
                    "state": "OR",
                    "zip": "97201",
                    "country": "US"
                }
            }))
            .send()
            .await
            .expect("Failed to send request");

        assert_eq!(res.status(), 202);
        let body: serde_json::Value = res.json().await.unwrap();
        let order_id = body["data"]["id"].as_i64().expect("Expected order ID");
        assert_eq!(body["data"]["status"].as_str().unwrap(), "queued");

        // Poll the app for the task_uuid (background task creates the workflow)
        let mut task_uuid = None;
        for _ in 0..15 {
            let order_res = client
                .get(format!("{}/orders/{}", base_url(), order_id))
                .send()
                .await
                .expect("Failed to get order");
            let order_body: serde_json::Value = order_res.json().await.unwrap();
            if let Some(uuid) = order_body["data"]["task_uuid"].as_str() {
                task_uuid = Some(uuid.to_string());
                break;
            }
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        }

        let task_uuid = task_uuid.expect("Background task did not create workflow within 15s");

        let task = wait_for_task_completion(&client, &task_uuid).await;

        let status = task["status"].as_str().unwrap();
        assert_eq!(status, "complete", "Expected task to complete, got: {}", status);
        assert_eq!(task["total_steps"].as_i64().unwrap(), 5);

        let steps = task["steps"].as_array().expect("Expected steps array");
        let completed = steps
            .iter()
            .filter(|s| s["current_state"].as_str() == Some("complete"))
            .count();
        assert_eq!(completed, 5, "Expected all 5 steps to complete, got {}", completed);

        println!("  E-commerce task (async): {} ({}/5 steps complete)", status, completed);
    }

    #[tokio::test]
    async fn test_analytics_pipeline_dispatches_and_processes() {
        let client = reqwest::Client::new();
        let res = client
            .post(format!("{}/analytics", base_url()))
            .json(&json!({
                "job_name": "completion_test_pipeline",
                "sources": ["sales", "inventory", "customers"],
                "date_range": {
                    "start_date": "2026-01-01",
                    "end_date": "2026-01-07"
                }
            }))
            .send()
            .await
            .expect("Failed to send request");

        assert_eq!(res.status(), 201);
        let body: serde_json::Value = res.json().await.unwrap();
        let task_uuid = body["data"]["task_uuid"]
            .as_str()
            .expect("Expected task_uuid in response");

        let task = wait_for_task_completion(&client, task_uuid).await;

        let status = task["status"].as_str().unwrap();
        assert_eq!(status, "complete", "Expected task to complete, got: {}", status);
        assert_eq!(task["total_steps"].as_i64().unwrap(), 8);

        let steps = task["steps"].as_array().expect("Expected steps array");
        let step_names: Vec<&str> = steps
            .iter()
            .map(|s| s["name"].as_str().unwrap())
            .collect();

        for expected in &[
            "extract_sales_data",
            "extract_inventory_data",
            "extract_customer_data",
        ] {
            assert!(
                step_names.contains(expected),
                "Expected step '{}' to be present",
                expected
            );
        }

        // At least one extract step was attempted (parallel dispatch works)
        let attempted = steps
            .iter()
            .filter(|s| {
                s["name"]
                    .as_str()
                    .map(|n| n.starts_with("extract_"))
                    .unwrap_or(false)
                    && s["attempts"].as_i64().unwrap_or(0) > 0
            })
            .count();
        assert!(attempted >= 1, "Expected at least one extract step to be attempted");

        // All steps must have reached "complete" state
        let completed = steps
            .iter()
            .filter(|s| s["current_state"].as_str() == Some("complete"))
            .count();
        assert_eq!(completed, 8, "Expected all 8 steps to complete, got {}", completed);

        println!(
            "  Analytics task: {} ({}/8 steps complete)",
            status, completed
        );
    }

    #[tokio::test]
    async fn test_user_registration_dispatches_and_processes() {
        let client = reqwest::Client::new();
        let res = client
            .post(format!("{}/services/register", base_url()))
            .json(&json!({
                "user_email": "completion-reg@example.com",
                "user_name": "Completion User",
                "plan": "pro"
            }))
            .send()
            .await
            .expect("Failed to send request");

        assert_eq!(res.status(), 201);
        let body: serde_json::Value = res.json().await.unwrap();
        let task_uuid = body["data"]["task_uuid"]
            .as_str()
            .expect("Expected task_uuid in response");

        let task = wait_for_task_completion(&client, task_uuid).await;

        // Task must fully complete (all steps successful)
        let status = task["status"].as_str().unwrap();
        assert_eq!(status, "complete", "Expected task to complete, got: {}", status);
        assert_eq!(task["total_steps"].as_i64().unwrap(), 5);

        // Verify diamond pattern: 5 steps present
        let steps = task["steps"].as_array().expect("Expected steps array");
        assert_eq!(steps.len(), 5);

        let step_names: Vec<&str> = steps
            .iter()
            .map(|s| s["name"].as_str().unwrap())
            .collect();

        for expected in &[
            "create_user_account",
            "setup_billing_profile",
            "initialize_preferences",
            "send_welcome_sequence",
            "update_user_status",
        ] {
            assert!(
                step_names.contains(expected),
                "Expected step '{}' to be present",
                expected
            );
        }

        // Handler dispatch works: first step was attempted
        let create_step = steps
            .iter()
            .find(|s| s["name"].as_str() == Some("create_user_account"))
            .expect("Expected create_user_account step");
        assert!(create_step["attempts"].as_i64().unwrap() >= 1);

        // All steps must have reached "complete" state
        let completed = steps
            .iter()
            .filter(|s| s["current_state"].as_str() == Some("complete"))
            .count();
        assert_eq!(completed, 5, "Expected all 5 steps to complete, got {}", completed);

        println!(
            "  User registration task: {} ({}/5 steps complete)",
            status, completed
        );
    }

    #[tokio::test]
    async fn test_customer_success_refund_dispatches_and_processes() {
        let client = reqwest::Client::new();
        let res = client
            .post(format!("{}/compliance/refund", base_url()))
            .json(&json!({
                "check_type": "refund",
                "namespace": "customer_success_rs",
                "ticket_id": "TICKET-COMP-CS",
                "customer_email": "cs-completion@example.com",
                "order_id": "ORD-20260101-COMP01",
                "refund_amount": 99.99,
                "reason": "Completion test - customer success"
            }))
            .send()
            .await
            .expect("Failed to send request");

        assert_eq!(res.status(), 201);
        let body: serde_json::Value = res.json().await.unwrap();
        let task_uuid = body["data"]["task_uuid"]
            .as_str()
            .expect("Expected task_uuid in response");

        let task = wait_for_task_completion(&client, task_uuid).await;

        let status = task["status"].as_str().unwrap();
        assert_eq!(status, "complete", "Expected task to complete, got: {}", status);
        assert_eq!(task["total_steps"].as_i64().unwrap(), 5);

        let steps = task["steps"].as_array().expect("Expected steps array");
        assert_eq!(steps.len(), 5);

        let step_names: Vec<&str> = steps
            .iter()
            .map(|s| s["name"].as_str().unwrap())
            .collect();

        for expected in &[
            "validate_refund_request",
            "check_refund_policy",
            "get_manager_approval",
            "execute_refund_workflow",
            "update_ticket_status",
        ] {
            assert!(
                step_names.contains(expected),
                "Expected step '{}' to be present",
                expected
            );
        }

        // Handler dispatch works: first step was attempted
        let validate_step = steps
            .iter()
            .find(|s| s["name"].as_str() == Some("validate_refund_request"))
            .expect("Expected validate_refund_request step");
        assert!(validate_step["attempts"].as_i64().unwrap() >= 1);

        // All steps must have reached "complete" state
        let completed = steps
            .iter()
            .filter(|s| s["current_state"].as_str() == Some("complete"))
            .count();
        assert_eq!(completed, 5, "Expected all 5 steps to complete, got {}", completed);

        println!(
            "  Customer success refund task: {} ({}/5 steps complete)",
            status, completed
        );
    }

    #[tokio::test]
    async fn test_payments_refund_dispatches_and_processes() {
        let client = reqwest::Client::new();

        // Create a payments refund task via the compliance route, which creates
        // tasks in both customer_success_rs and payments_rs namespaces.
        // We extract and verify the payments task UUID from the response.
        let res = client
            .post(format!("{}/compliance/refund", base_url()))
            .json(&json!({
                "check_type": "refund",
                "namespace": "payments_rs",
                "ticket_id": "TICKET-COMP-PAY",
                "customer_email": "pay-completion@example.com",
                "order_id": "ORD-20260101-PAY01",
                "refund_amount": 75.50,
                "payment_id": "pay_comptest123",
                "reason": "Completion test - payments refund"
            }))
            .send()
            .await
            .expect("Failed to send request");

        assert_eq!(res.status(), 201);
        let body: serde_json::Value = res.json().await.unwrap();
        let task_uuid = body["data"]["payments_task_uuid"]
            .as_str()
            .expect("Expected payments_task_uuid in response");

        let task = wait_for_task_completion(&client, task_uuid).await;

        let status = task["status"].as_str().unwrap();
        assert_eq!(status, "complete", "Expected task to complete, got: {}", status);
        assert_eq!(task["total_steps"].as_i64().unwrap(), 4);

        let steps = task["steps"].as_array().expect("Expected steps array");
        assert_eq!(steps.len(), 4);

        let step_names: Vec<&str> = steps
            .iter()
            .map(|s| s["name"].as_str().unwrap())
            .collect();

        for expected in &[
            "validate_payment_eligibility",
            "process_gateway_refund",
            "update_payment_records",
            "notify_customer",
        ] {
            assert!(
                step_names.contains(expected),
                "Expected step '{}' to be present",
                expected
            );
        }

        // Handler dispatch works: first step was attempted
        let validate_step = steps
            .iter()
            .find(|s| s["name"].as_str() == Some("validate_payment_eligibility"))
            .expect("Expected validate_payment_eligibility step");
        assert!(validate_step["attempts"].as_i64().unwrap() >= 1);

        // All steps must have reached "complete" state
        let completed = steps
            .iter()
            .filter(|s| s["current_state"].as_str() == Some("complete"))
            .count();
        assert_eq!(completed, 4, "Expected all 4 steps to complete, got {}", completed);

        println!(
            "  Payments refund task: {} ({}/4 steps complete)",
            status, completed
        );
    }

    #[tokio::test]
    async fn test_create_refund_compliance_check() {
        let client = reqwest::Client::new();
        let res = client
            .post(format!("{}/compliance/refund", base_url()))
            .json(&json!({
                "check_type": "refund",
                "namespace": "customer_success_rs",
                "ticket_id": "TICKET-1234",
                "customer_email": "customer@example.com",
                "order_id": "ORD-20251115-ABC123",
                "refund_amount": 149.99,
                "reason": "Product defective"
            }))
            .send()
            .await
            .expect("Failed to send request");

        assert_eq!(res.status(), 201, "Expected 201 Created");

        let body: serde_json::Value = res.json().await.expect("Failed to parse response");
        assert!(
            body["data"]["id"].is_number(),
            "Response should contain compliance check ID"
        );
        assert_eq!(body["data"]["check_type"].as_str().unwrap(), "refund");
        assert_eq!(
            body["data"]["namespace"].as_str().unwrap(),
            "customer_success_rs"
        );
    }
}
