-- Create app-specific databases for each example application.
-- Each app stores its domain models (orders, analytics_jobs, etc.) in its own database,
-- separate from tasker's internal database.

CREATE DATABASE example_rails OWNER tasker;
CREATE DATABASE example_fastapi OWNER tasker;
CREATE DATABASE example_bun OWNER tasker;
CREATE DATABASE example_axum OWNER tasker;
