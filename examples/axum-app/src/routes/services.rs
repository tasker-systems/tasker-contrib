//! Microservices user registration routes.
//!
//! POST /services/register - Create a user registration workflow
//! GET  /services/:id      - Retrieve a service request by ID

use axum::extract::Path;
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Extension, Json, Router};
use tracing::{error, info};

use crate::db::AppDb;
use crate::models::{ApiResponse, CreateServiceRequest, ServiceRequest, ServiceRequestResponse};

/// Build the services router.
pub fn router() -> Router {
    Router::new()
        .route("/services/register", post(create_registration))
        .route("/services/{id}", get(get_service_request))
}

/// Create a user registration service request and submit a microservices workflow to Tasker.
///
/// The microservices workflow coordinates user account creation across multiple services:
/// CreateUser -> (SetupBilling || InitPreferences) -> SendWelcome -> UpdateStatus
async fn create_registration(
    Extension(pool): Extension<AppDb>,
    Json(req): Json<CreateServiceRequest>,
) -> Result<(StatusCode, Json<ApiResponse<ServiceRequestResponse>>), StatusCode> {
    let payload = serde_json::json!({
        "user_email": req.user_email,
        "user_name": req.user_name,
        "plan": req.plan.as_deref().unwrap_or("free"),
    });

    // Insert service request into application database
    let service_req: ServiceRequest = sqlx::query_as(
        r#"
        INSERT INTO service_requests (service_type, user_email, payload, status)
        VALUES ('user_registration', $1, $2, 'pending')
        RETURNING *
        "#,
    )
    .bind(&req.user_email)
    .bind(&payload)
    .fetch_one(&pool)
    .await
    .map_err(|e| {
        error!("Failed to insert service request: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    info!(
        "Service request {} created for user registration: {}",
        service_req.id, req.user_email
    );

    // Build the Tasker task request for the microservices user registration workflow.
    // Context uses flat fields to match the handler contract:
    //   create_user_account reads context["email"], context["full_name"], context["plan"], etc.
    let task_payload = serde_json::json!({
        "name": "user_registration",
        "namespace": "microservices_rs",
        "version": "1.0.0",
        "initiator": "axum-example-app",
        "source_system": "example-axum",
        "reason": format!("User registration for {}", req.user_email),
        "context": {
            "email": req.user_email,
            "full_name": req.user_name,
            "plan": req.plan.as_deref().unwrap_or("free"),
            "source": "axum-example-app",
            "app_service_request_id": service_req.id
        }
    });

    // Submit task to Tasker orchestration
    let task_uuid = match submit_task_to_orchestration(&task_payload).await {
        Ok(uuid) => Some(uuid),
        Err(e) => {
            error!("Failed to submit registration task to orchestration: {}", e);
            None
        }
    };

    // Update service request with task UUID
    if let Some(ref uuid) = task_uuid {
        let _ = sqlx::query(
            "UPDATE service_requests SET task_uuid = $1, status = 'processing' WHERE id = $2",
        )
        .bind(uuid)
        .bind(service_req.id)
        .execute(&pool)
        .await;
    }

    let response = ServiceRequestResponse {
        id: service_req.id,
        service_type: service_req.service_type,
        user_email: service_req.user_email,
        status: if task_uuid.is_some() {
            "processing".to_string()
        } else {
            "pending".to_string()
        },
        task_uuid,
        created_at: service_req.created_at,
    };

    Ok((
        StatusCode::CREATED,
        Json(ApiResponse {
            data: response,
            message: "User registration started".to_string(),
        }),
    ))
}

/// Retrieve a service request by ID.
async fn get_service_request(
    Extension(pool): Extension<AppDb>,
    Path(id): Path<i32>,
) -> Result<Json<ApiResponse<ServiceRequest>>, StatusCode> {
    let service_req: ServiceRequest =
        sqlx::query_as("SELECT * FROM service_requests WHERE id = $1")
            .bind(id)
            .fetch_optional(&pool)
            .await
            .map_err(|e| {
                error!("Failed to query service request: {}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?
            .ok_or(StatusCode::NOT_FOUND)?;

    Ok(Json(ApiResponse {
        data: service_req,
        message: "Service request retrieved".to_string(),
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
