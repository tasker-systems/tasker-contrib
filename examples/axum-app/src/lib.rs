//! # Axum Example Application Library
//!
//! Exposes the Axum router and modules so integration tests can create
//! an in-process server without requiring `cargo run` in another terminal.

pub mod db;
pub mod handler_registry;
pub mod handlers;
pub mod models;
pub mod routes;

use axum::{Extension, Router};
use sqlx::PgPool;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;

/// Build the Axum router with all route modules and middleware.
///
/// The caller is responsible for providing a connected database pool.
/// This function does NOT start a server or bootstrap the Tasker worker.
pub fn create_app(app_db: PgPool) -> Router {
    Router::new()
        .merge(routes::orders::router())
        .merge(routes::analytics::router())
        .merge(routes::services::router())
        .merge(routes::compliance::router())
        .layer(Extension(app_db))
        .layer(TraceLayer::new_for_http())
        .layer(CorsLayer::permissive())
}
