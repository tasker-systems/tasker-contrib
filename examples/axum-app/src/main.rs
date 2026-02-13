//! # Axum Example Application
//!
//! A standalone Axum web application demonstrating 4 Tasker workflow orchestration
//! patterns with framework-native HTTP handling.
//!
//! ## Workflow Patterns
//!
//! 1. **E-commerce Order Processing** (5 steps, linear chain)
//! 2. **Data Pipeline Analytics** (8 steps, DAG with parallel extraction)
//! 3. **Microservices User Registration** (5 steps, diamond pattern)
//! 4. **Team Scaling with Namespace Isolation** (9 steps, 2 namespaces)
//!
//! ## Architecture
//!
//! - Axum handles HTTP routing and request/response lifecycle
//! - SQLx manages the application-specific database (domain models)
//! - Tasker worker runs in the background for workflow step execution
//! - Tasker client communicates with orchestration for task creation

mod db;
mod handler_registry;
mod handlers;
mod models;
mod routes;

use std::sync::Arc;

use axum::{Extension, Router};
use sqlx::postgres::PgPoolOptions;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;
use tracing::info;

use tasker_worker::worker::handlers::{HandlerDispatchConfig, HandlerDispatchService, NoOpCallback};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();

    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "example_axum_app=debug,tasker_worker=info,tower_http=debug".into()),
        )
        .init();

    info!("Starting Axum example application");

    // Application database pool (for domain models: orders, analytics_jobs, etc.)
    let app_db_url = db::pool_from_env();
    let app_db = PgPoolOptions::new()
        .max_connections(10)
        .connect(&app_db_url)
        .await?;

    info!("Connected to application database");

    // Run application-specific migrations
    sqlx::migrate!("./migrations").run(&app_db).await?;
    info!("Application migrations complete");

    // Bootstrap the Tasker worker in the background.
    // Web and gRPC servers are disabled in config/worker.toml because
    // Axum provides its own HTTP server.
    let mut worker_handle = tasker_worker::WorkerBootstrap::bootstrap().await?;
    info!("Tasker worker bootstrapped");

    // Create handler registry and wire it into the dispatch system.
    // WorkerBootstrap only creates infrastructure (channels, actors, DB pools).
    // The application is responsible for providing a StepHandlerRegistry so the
    // dispatch service can route steps to the correct handler functions.
    let registry = Arc::new(handler_registry::AxumHandlerRegistry::new());
    info!(
        "Handler registry initialized with {} handlers",
        registry.handler_count()
    );

    if let Some(dispatch_handles) = worker_handle.take_dispatch_handles() {
        let dispatch_config = HandlerDispatchConfig::default();
        let (dispatch_service, _capacity_checker) = HandlerDispatchService::with_callback(
            dispatch_handles.dispatch_receiver,
            dispatch_handles.completion_sender,
            registry,
            dispatch_config,
            Arc::new(NoOpCallback),
        );

        tokio::spawn(async move {
            dispatch_service.run().await;
        });
        info!("Handler dispatch service started");
    }

    // Build the Axum router with all route modules
    let app = Router::new()
        .merge(routes::orders::router())
        .merge(routes::analytics::router())
        .merge(routes::services::router())
        .merge(routes::compliance::router())
        .layer(Extension(app_db))
        .layer(TraceLayer::new_for_http())
        .layer(CorsLayer::permissive());

    // Bind and serve
    let bind_addr = "0.0.0.0:3000";
    let listener = tokio::net::TcpListener::bind(bind_addr).await?;
    info!("Listening on {}", bind_addr);

    axum::serve(listener, app).await?;
    Ok(())
}
