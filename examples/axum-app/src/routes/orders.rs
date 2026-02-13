//! E-commerce order processing routes.
//!
//! POST /orders     - Create a new order and kick off the e-commerce workflow
//! GET  /orders/:id - Retrieve an order by ID (includes task status)

use axum::extract::Path;
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Extension, Json, Router};
use tracing::{error, info};

use crate::db::AppDb;
use crate::models::{ApiResponse, CreateOrderRequest, Order, OrderResponse};

/// Build the orders router.
pub fn router() -> Router {
    Router::new()
        .route("/orders", post(create_order))
        .route("/orders/{id}", get(get_order))
}

/// Create a new order and submit an e-commerce workflow task to Tasker.
///
/// 1. Insert an order record with status=pending into the app database
/// 2. Create a Tasker task via the orchestration REST API
/// 3. Update the order with the returned task UUID
/// 4. Return the order response
async fn create_order(
    Extension(pool): Extension<AppDb>,
    Json(req): Json<CreateOrderRequest>,
) -> Result<(StatusCode, Json<ApiResponse<OrderResponse>>), StatusCode> {
    // Calculate total from cart items
    let total: f64 = req
        .cart_items
        .iter()
        .map(|item| item.unit_price * item.quantity as f64)
        .sum();
    let items_json = serde_json::to_value(&req.cart_items).unwrap_or_default();

    // Insert order into application database
    let order: Order = sqlx::query_as(
        r#"
        INSERT INTO orders (customer_email, items, total, status)
        VALUES ($1, $2, $3, 'pending')
        RETURNING *
        "#,
    )
    .bind(&req.customer_email)
    .bind(&items_json)
    .bind(total)
    .fetch_one(&pool)
    .await
    .map_err(|e| {
        error!("Failed to insert order: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    info!("Order {} created for {}", order.id, req.customer_email);

    // Build the Tasker task request for e-commerce order processing.
    // We use the orchestration REST API directly via reqwest.
    let task_payload = serde_json::json!({
        "name": "ecommerce_order_processing",
        "namespace": "ecommerce_rs",
        "version": "1.0.0",
        "initiator": "axum-example-app",
        "source_system": "example-axum",
        "reason": "E-commerce order placed via Axum API",
        "context": {
            "cart_items": req.cart_items.iter().map(|item| {
                serde_json::json!({
                    "product_id": item.sku.parse::<i64>().unwrap_or(1),
                    "quantity": item.quantity
                })
            }).collect::<Vec<_>>(),
            "customer_info": {
                "email": req.customer_email,
                "name": req.customer_email.split('@').next().unwrap_or("Customer"),
                "phone": null
            },
            "payment_info": {
                "method": "credit_card",
                "token": req.payment_token,
                "amount": total
            },
            "shipping_address": req.shipping_address,
            "app_order_id": order.id
        }
    });

    // Submit task to Tasker orchestration
    let task_uuid = match submit_task_to_orchestration(&task_payload).await {
        Ok(uuid) => Some(uuid),
        Err(e) => {
            error!("Failed to submit task to orchestration: {}", e);
            None
        }
    };

    // Update order with task UUID and status
    if let Some(ref uuid) = task_uuid {
        let _ = sqlx::query("UPDATE orders SET task_uuid = $1, status = 'processing' WHERE id = $2")
            .bind(uuid)
            .bind(order.id)
            .execute(&pool)
            .await;
    }

    let response = OrderResponse {
        id: order.id,
        customer_email: order.customer_email,
        status: if task_uuid.is_some() {
            "processing".to_string()
        } else {
            "pending".to_string()
        },
        task_uuid,
        created_at: order.created_at,
    };

    Ok((
        StatusCode::CREATED,
        Json(ApiResponse {
            data: response,
            message: "Order created successfully".to_string(),
        }),
    ))
}

/// Retrieve an order by ID.
async fn get_order(
    Extension(pool): Extension<AppDb>,
    Path(id): Path<i32>,
) -> Result<Json<ApiResponse<Order>>, StatusCode> {
    let order: Order = sqlx::query_as("SELECT * FROM orders WHERE id = $1")
        .bind(id)
        .fetch_optional(&pool)
        .await
        .map_err(|e| {
            error!("Failed to query order: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .ok_or(StatusCode::NOT_FOUND)?;

    Ok(Json(ApiResponse {
        data: order,
        message: "Order retrieved".to_string(),
    }))
}

/// Submit a task to the Tasker orchestration REST API and return the task UUID.
async fn submit_task_to_orchestration(
    payload: &serde_json::Value,
) -> anyhow::Result<uuid::Uuid> {
    let orchestration_url =
        std::env::var("ORCHESTRATION_URL").unwrap_or_else(|_| "http://localhost:8080".to_string());

    let client = reqwest::Client::new();
    let response = client
        .post(format!("{}/v1/tasks", orchestration_url))
        .json(payload)
        .send()
        .await?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        anyhow::bail!("Orchestration returned {}: {}", status, body);
    }

    let body: serde_json::Value = response.json().await?;
    let task_uuid_str = body["task_uuid"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("Missing task_uuid in orchestration response"))?;
    let task_uuid = uuid::Uuid::parse_str(task_uuid_str)?;
    Ok(task_uuid)
}
