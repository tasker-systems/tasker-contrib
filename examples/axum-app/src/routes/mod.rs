//! HTTP route modules for the Axum example application.
//!
//! Each module defines Axum routes for one of the 4 workflow patterns:
//! - `orders`: E-commerce order processing (Blog Post 1)
//! - `analytics`: Data pipeline analytics (Blog Post 2)
//! - `services`: Microservices user registration (Blog Post 3)
//! - `compliance`: Team scaling with namespace isolation (Blog Post 4)

pub mod analytics;
pub mod compliance;
pub mod orders;
pub mod services;
