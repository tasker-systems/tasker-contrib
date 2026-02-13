//! Database helpers for the Axum example application.
//!
//! Provides type aliases and extractors for the application-specific database pool.
//! This pool connects to the example_axum database for domain model storage,
//! separate from Tasker's internal database.

use sqlx::PgPool;

/// Type alias for the application database pool.
pub type AppDb = PgPool;

/// Extract the application database pool from Axum extensions.
///
/// Usage in route handlers:
/// ```ignore
/// async fn my_handler(
///     Extension(pool): Extension<AppDb>,
/// ) -> impl IntoResponse {
///     // Use pool for domain model queries
/// }
/// ```
pub fn pool_from_env() -> String {
    std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgresql://tasker:tasker@localhost:5432/example_axum".to_string())
}
