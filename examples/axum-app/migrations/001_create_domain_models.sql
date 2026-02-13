-- Domain models for the Axum example application.
-- These tables store application-specific data (orders, analytics jobs, etc.)
-- in the app's own database, separate from Tasker's internal database.

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    customer_email VARCHAR(255) NOT NULL,
    items JSONB NOT NULL DEFAULT '[]',
    total DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    task_uuid UUID,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS analytics_jobs (
    id SERIAL PRIMARY KEY,
    job_name VARCHAR(255) NOT NULL,
    source_config JSONB NOT NULL DEFAULT '{}',
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    task_uuid UUID,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS service_requests (
    id SERIAL PRIMARY KEY,
    service_type VARCHAR(100) NOT NULL,
    user_email VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}',
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    task_uuid UUID,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS compliance_checks (
    id SERIAL PRIMARY KEY,
    check_type VARCHAR(100) NOT NULL,
    namespace VARCHAR(100) NOT NULL,
    ticket_id VARCHAR(100),
    payload JSONB NOT NULL DEFAULT '{}',
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    task_uuid UUID,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Index for task_uuid lookups on all tables
CREATE INDEX IF NOT EXISTS idx_orders_task_uuid ON orders(task_uuid);
CREATE INDEX IF NOT EXISTS idx_analytics_jobs_task_uuid ON analytics_jobs(task_uuid);
CREATE INDEX IF NOT EXISTS idx_service_requests_task_uuid ON service_requests(task_uuid);
CREATE INDEX IF NOT EXISTS idx_compliance_checks_task_uuid ON compliance_checks(task_uuid);
