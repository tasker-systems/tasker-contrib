//! Domain models for the Axum example application.
//!
//! These structs map to the tables in the example_axum database and represent
//! the application's business entities. Each model includes a task_uuid field
//! that links the domain record to its corresponding Tasker workflow task.

use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize};
use sqlx::types::BigDecimal;
use uuid::Uuid;

// ============================================================================
// Database Models (sqlx::FromRow)
// ============================================================================

/// An e-commerce order tracked in the application database.
#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct Order {
    pub id: i32,
    pub customer_email: String,
    pub items: serde_json::Value,
    pub total: BigDecimal,
    pub status: String,
    pub task_uuid: Option<Uuid>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

/// An analytics pipeline job tracked in the application database.
#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct AnalyticsJob {
    pub id: i32,
    pub job_name: String,
    pub source_config: serde_json::Value,
    pub status: String,
    pub task_uuid: Option<Uuid>,
    pub started_at: Option<NaiveDateTime>,
    pub completed_at: Option<NaiveDateTime>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

/// A microservices coordination request tracked in the application database.
#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct ServiceRequest {
    pub id: i32,
    pub service_type: String,
    pub user_email: String,
    pub payload: serde_json::Value,
    pub status: String,
    pub task_uuid: Option<Uuid>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

/// A compliance check request tracked in the application database.
#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct ComplianceCheck {
    pub id: i32,
    pub check_type: String,
    pub namespace: String,
    pub ticket_id: Option<String>,
    pub payload: serde_json::Value,
    pub status: String,
    pub task_uuid: Option<Uuid>,
    pub created_at: NaiveDateTime,
    pub updated_at: NaiveDateTime,
}

// ============================================================================
// Request Models (Deserialize from JSON input)
// ============================================================================

/// Request body for creating a new order.
#[derive(Debug, Deserialize)]
pub struct CreateOrderRequest {
    pub customer_email: String,
    pub cart_items: Vec<CartItemInput>,
    pub payment_token: String,
    pub shipping_address: ShippingAddress,
}

/// A single cart item in an order creation request.
#[derive(Debug, Serialize, Deserialize)]
pub struct CartItemInput {
    pub sku: String,
    pub name: String,
    pub quantity: i64,
    pub unit_price: f64,
}

/// Shipping address for an order.
#[derive(Debug, Serialize, Deserialize)]
pub struct ShippingAddress {
    pub street: String,
    pub city: String,
    pub state: String,
    pub zip: String,
    pub country: String,
}

/// Request body for creating a new analytics pipeline job.
#[derive(Debug, Deserialize)]
pub struct CreateAnalyticsJobRequest {
    pub job_name: String,
    pub sources: Vec<String>,
    pub date_range: Option<DateRange>,
}

/// Date range filter for analytics jobs.
#[derive(Debug, Serialize, Deserialize)]
pub struct DateRange {
    pub start_date: String,
    pub end_date: String,
}

/// Request body for creating a new service request (user registration).
#[derive(Debug, Deserialize)]
pub struct CreateServiceRequest {
    pub user_email: String,
    pub user_name: String,
    pub plan: Option<String>,
}

/// Request body for creating a new compliance check (refund processing).
#[derive(Debug, Deserialize)]
pub struct CreateComplianceCheckRequest {
    pub check_type: String,
    pub namespace: String,
    pub ticket_id: Option<String>,
    pub customer_email: String,
    pub order_id: String,
    pub refund_amount: f64,
    pub reason: String,
}

// ============================================================================
// Response Models
// ============================================================================

/// Generic API response wrapper.
#[derive(Debug, Serialize)]
pub struct ApiResponse<T: Serialize> {
    pub data: T,
    pub message: String,
}

/// Response for a created order.
#[derive(Debug, Serialize)]
pub struct OrderResponse {
    pub id: i32,
    pub customer_email: String,
    pub status: String,
    pub task_uuid: Option<Uuid>,
    pub created_at: NaiveDateTime,
}

/// Response for a created analytics job.
#[derive(Debug, Serialize)]
pub struct AnalyticsJobResponse {
    pub id: i32,
    pub job_name: String,
    pub status: String,
    pub task_uuid: Option<Uuid>,
    pub created_at: NaiveDateTime,
}

/// Response for a created service request.
#[derive(Debug, Serialize)]
pub struct ServiceRequestResponse {
    pub id: i32,
    pub service_type: String,
    pub user_email: String,
    pub status: String,
    pub task_uuid: Option<Uuid>,
    pub created_at: NaiveDateTime,
}

/// Response for a created compliance check.
#[derive(Debug, Serialize)]
pub struct ComplianceCheckResponse {
    pub id: i32,
    pub check_type: String,
    pub namespace: String,
    pub status: String,
    pub task_uuid: Option<Uuid>,
    pub payments_task_uuid: Option<Uuid>,
    pub created_at: NaiveDateTime,
}
