//! Team scaling with namespace isolation routes (compliance/refund processing).
//!
//! POST /compliance/refund - Create a refund processing workflow across two namespaces
//! GET  /compliance/:id    - Retrieve a compliance check by ID

use axum::extract::Path;
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Extension, Json, Router};
use tracing::{error, info};

use crate::db::AppDb;
use crate::models::{
    ApiResponse, ComplianceCheck, ComplianceCheckResponse, CreateComplianceCheckRequest,
};

/// Build the compliance router.
pub fn router() -> Router {
    Router::new()
        .route("/compliance/refund", post(create_refund_check))
        .route("/compliance/{id}", get(get_compliance_check))
}

/// Create a refund processing compliance check spanning two namespaces.
///
/// The team scaling workflow demonstrates namespace isolation with:
/// - Customer Success namespace (5 steps): validate, check policy, manager approval,
///   execute refund workflow, update ticket
/// - Payments namespace (4 steps): validate eligibility, process gateway refund,
///   update records, notify customer
async fn create_refund_check(
    Extension(pool): Extension<AppDb>,
    Json(req): Json<CreateComplianceCheckRequest>,
) -> Result<(StatusCode, Json<ApiResponse<ComplianceCheckResponse>>), StatusCode> {
    let payload = serde_json::json!({
        "customer_email": req.customer_email,
        "order_id": req.order_id,
        "refund_amount": req.refund_amount,
        "reason": req.reason,
    });

    // Insert compliance check into application database
    let check: ComplianceCheck = sqlx::query_as(
        r#"
        INSERT INTO compliance_checks (check_type, namespace, ticket_id, payload, status)
        VALUES ($1, $2, $3, $4, 'pending')
        RETURNING *
        "#,
    )
    .bind(&req.check_type)
    .bind(&req.namespace)
    .bind(&req.ticket_id)
    .bind(&payload)
    .fetch_one(&pool)
    .await
    .map_err(|e| {
        error!("Failed to insert compliance check: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    info!(
        "Compliance check {} created: {} in namespace {}",
        check.id, req.check_type, req.namespace
    );

    // Determine which namespace workflow to submit based on the request.
    // For the team scaling pattern, we create tasks in both namespaces.
    let cs_task_payload = serde_json::json!({
        "name": "customer_success_process_refund",
        "namespace": "customer_success_rs",
        "version": "1.0.0",
        "initiator": "axum-example-app",
        "source_system": "example-axum",
        "reason": format!("Refund request: {} - {}", req.order_id, req.reason),
        "context": {
            "ticket_id": req.ticket_id.as_deref().unwrap_or("TICKET-000"),
            "customer_email": req.customer_email,
            "order_id": req.order_id,
            "refund_amount": req.refund_amount,
            "reason": req.reason,
            "app_compliance_check_id": check.id
        }
    });

    let payments_task_payload = serde_json::json!({
        "name": "payments_process_refund",
        "namespace": "payments_rs",
        "version": "1.0.0",
        "initiator": "axum-example-app",
        "source_system": "example-axum",
        "reason": format!("Payment refund: {} - ${:.2}", req.order_id, req.refund_amount),
        "context": {
            "order_id": req.order_id,
            "customer_email": req.customer_email,
            "refund_amount": req.refund_amount,
            "payment_method": "original_method",
            "reason": req.reason,
            "app_compliance_check_id": check.id
        }
    });

    // Submit both tasks to orchestration (customer success + payments)
    let cs_task_uuid = match submit_task_to_orchestration(&cs_task_payload).await {
        Ok(uuid) => Some(uuid),
        Err(e) => {
            error!(
                "Failed to submit customer success task to orchestration: {}",
                e
            );
            None
        }
    };

    let _payments_task_uuid = match submit_task_to_orchestration(&payments_task_payload).await {
        Ok(uuid) => Some(uuid),
        Err(e) => {
            error!("Failed to submit payments task to orchestration: {}", e);
            None
        }
    };

    // Use the customer success task UUID as the primary reference
    let task_uuid = cs_task_uuid;

    // Update compliance check with task UUID
    if let Some(ref uuid) = task_uuid {
        let _ = sqlx::query(
            "UPDATE compliance_checks SET task_uuid = $1, status = 'processing' WHERE id = $2",
        )
        .bind(uuid)
        .bind(check.id)
        .execute(&pool)
        .await;
    }

    let response = ComplianceCheckResponse {
        id: check.id,
        check_type: check.check_type,
        namespace: check.namespace,
        status: if task_uuid.is_some() {
            "processing".to_string()
        } else {
            "pending".to_string()
        },
        task_uuid,
        created_at: check.created_at,
    };

    Ok((
        StatusCode::CREATED,
        Json(ApiResponse {
            data: response,
            message: "Refund compliance check created across both namespaces".to_string(),
        }),
    ))
}

/// Retrieve a compliance check by ID.
async fn get_compliance_check(
    Extension(pool): Extension<AppDb>,
    Path(id): Path<i32>,
) -> Result<Json<ApiResponse<ComplianceCheck>>, StatusCode> {
    let check: ComplianceCheck = sqlx::query_as("SELECT * FROM compliance_checks WHERE id = $1")
        .bind(id)
        .fetch_optional(&pool)
        .await
        .map_err(|e| {
            error!("Failed to query compliance check: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .ok_or(StatusCode::NOT_FOUND)?;

    Ok(Json(ApiResponse {
        data: check,
        message: "Compliance check retrieved".to_string(),
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
