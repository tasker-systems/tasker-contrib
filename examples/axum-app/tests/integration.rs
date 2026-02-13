//! # Integration Tests
//!
//! These tests verify the Axum example application endpoints by sending HTTP
//! requests to the running server. They require the full infrastructure stack
//! (PostgreSQL, Tasker Orchestration) to be running.
//!
//! ## Running Tests
//!
//! ```bash
//! # 1. Start shared infrastructure
//! cd examples/ && docker-compose up -d
//!
//! # 2. Start the Axum app (in another terminal)
//! cd examples/axum-app && cargo run
//!
//! # 3. Run tests
//! cd examples/axum-app && cargo test
//! ```

#[cfg(test)]
mod tests {
    use serde_json::json;

    fn base_url() -> String {
        std::env::var("APP_BASE_URL").unwrap_or_else(|_| "http://localhost:3000".to_string())
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
