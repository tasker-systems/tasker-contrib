//! Data pipeline analytics routes.
//!
//! POST /analytics     - Create a new analytics pipeline job
//! GET  /analytics/:id - Retrieve an analytics job by ID

use axum::extract::Path;
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Extension, Json, Router};
use tracing::{error, info};

use crate::db::AppDb;
use crate::models::{AnalyticsJob, AnalyticsJobResponse, ApiResponse, CreateAnalyticsJobRequest};

/// Build the analytics router.
pub fn router() -> Router {
    Router::new()
        .route("/analytics", post(create_analytics_job))
        .route("/analytics/{id}", get(get_analytics_job))
}

/// Create a new analytics pipeline job and submit a data pipeline workflow to Tasker.
///
/// The data pipeline workflow extracts data from 3 parallel sources (sales, inventory,
/// customers), transforms each, aggregates metrics, and generates business insights.
async fn create_analytics_job(
    Extension(pool): Extension<AppDb>,
    Json(req): Json<CreateAnalyticsJobRequest>,
) -> Result<(StatusCode, Json<ApiResponse<AnalyticsJobResponse>>), StatusCode> {
    let source_config = serde_json::json!({
        "sources": req.sources,
        "date_range": req.date_range,
    });

    // Insert analytics job into application database
    let job: AnalyticsJob = sqlx::query_as(
        r#"
        INSERT INTO analytics_jobs (job_name, source_config, status, started_at)
        VALUES ($1, $2, 'pending', NOW())
        RETURNING *
        "#,
    )
    .bind(&req.job_name)
    .bind(&source_config)
    .fetch_one(&pool)
    .await
    .map_err(|e| {
        error!("Failed to insert analytics job: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    info!("Analytics job {} created: {}", job.id, req.job_name);

    // Build the Tasker task request for the data pipeline workflow
    let task_payload = serde_json::json!({
        "name": "analytics_pipeline",
        "namespace": "data_pipeline_rs",
        "version": "1.0.0",
        "initiator": "axum-example-app",
        "source_system": "example-axum",
        "reason": format!("Analytics pipeline job: {}", req.job_name),
        "context": {
            "job_name": req.job_name,
            "sources": req.sources,
            "date_range": req.date_range,
            "app_job_id": job.id
        }
    });

    // Submit task to Tasker orchestration
    let task_uuid = match submit_task_to_orchestration(&task_payload).await {
        Ok(uuid) => Some(uuid),
        Err(e) => {
            error!("Failed to submit analytics task to orchestration: {}", e);
            None
        }
    };

    // Update job with task UUID
    if let Some(ref uuid) = task_uuid {
        let _ = sqlx::query(
            "UPDATE analytics_jobs SET task_uuid = $1, status = 'processing' WHERE id = $2",
        )
        .bind(uuid)
        .bind(job.id)
        .execute(&pool)
        .await;
    }

    let response = AnalyticsJobResponse {
        id: job.id,
        job_name: job.job_name,
        status: if task_uuid.is_some() {
            "processing".to_string()
        } else {
            "pending".to_string()
        },
        task_uuid,
        created_at: job.created_at,
    };

    Ok((
        StatusCode::CREATED,
        Json(ApiResponse {
            data: response,
            message: "Analytics job created successfully".to_string(),
        }),
    ))
}

/// Retrieve an analytics job by ID.
async fn get_analytics_job(
    Extension(pool): Extension<AppDb>,
    Path(id): Path<i32>,
) -> Result<Json<ApiResponse<AnalyticsJob>>, StatusCode> {
    let job: AnalyticsJob = sqlx::query_as("SELECT * FROM analytics_jobs WHERE id = $1")
        .bind(id)
        .fetch_optional(&pool)
        .await
        .map_err(|e| {
            error!("Failed to query analytics job: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .ok_or(StatusCode::NOT_FOUND)?;

    Ok(Json(ApiResponse {
        data: job,
        message: "Analytics job retrieved".to_string(),
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
