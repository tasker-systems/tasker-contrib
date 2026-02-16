# Axum Example Application

A standalone Axum web application demonstrating 4 Tasker workflow orchestration patterns with native Rust handlers.

## Architecture

```
                          Axum App (:3000)
                     ┌──────────────────────┐
    HTTP Requests    │  Routes (orders,      │
    ───────────────► │  analytics, services, │
                     │  compliance)          │
                     └──────┬───────────────┘
                            │
              ┌─────────────┼─────────────────┐
              │             │                  │
              ▼             ▼                  ▼
         App Database   Tasker Worker    Orchestration API
        (example_axum)  (background)     (localhost:8080)
              │                                │
              │         ┌──────────────────────┘
              │         │
              ▼         ▼
          PostgreSQL (shared)
```

- **Axum** handles HTTP routing and request/response lifecycle
- **SQLx** manages the application-specific database (domain models)
- **Tasker Worker** runs in the background, with web/gRPC disabled
- **Orchestration API** receives task creation requests via REST

## Workflows Implemented

### 1. E-commerce Order Processing (5 steps)

Linear chain: ValidateCart -> ProcessPayment -> UpdateInventory -> CreateOrder -> SendConfirmation

```bash
curl -X POST http://localhost:3000/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customer_email": "alice@example.com",
    "cart_items": [
      {"sku": "1", "name": "Widget A", "quantity": 2, "unit_price": 29.99}
    ],
    "payment_token": "tok_test_success",
    "shipping_address": {
      "street": "123 Main St", "city": "Portland",
      "state": "OR", "zip": "97201", "country": "US"
    }
  }'
```

### 2. Data Pipeline Analytics (8 steps)

DAG pattern: 3 parallel extracts -> 3 transforms -> aggregate -> insights

```bash
curl -X POST http://localhost:3000/analytics \
  -H "Content-Type: application/json" \
  -d '{
    "job_name": "monthly_report",
    "sources": ["sales", "inventory", "customers"],
    "date_range": {"start_date": "2025-10-01", "end_date": "2025-12-31"}
  }'
```

### 3. Microservices User Registration (5 steps)

Diamond pattern: CreateUser -> (SetupBilling || InitPreferences) -> SendWelcome -> UpdateStatus

```bash
curl -X POST http://localhost:3000/services/register \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "newuser@example.com",
    "user_name": "New User",
    "plan": "pro"
  }'
```

### 4. Team Scaling with Namespace Isolation (9 steps)

Two namespaces with cross-namespace coordination:
- **Customer Success** (5 steps): ValidateRefund -> CheckPolicy -> ManagerApproval -> ExecuteRefund -> UpdateTicket
- **Payments** (4 steps): ValidateEligibility -> ProcessGatewayRefund -> UpdateRecords -> NotifyCustomer

```bash
curl -X POST http://localhost:3000/compliance/refund \
  -H "Content-Type: application/json" \
  -d '{
    "check_type": "refund",
    "namespace": "customer_success_rs",
    "ticket_id": "TICKET-1234",
    "customer_email": "customer@example.com",
    "order_id": "ORD-20251115-ABC123",
    "refund_amount": 149.99,
    "reason": "Product defective"
  }'
```

## Quick Start

### 1. Start shared infrastructure

```bash
cd examples/
docker-compose up -d
# Wait for orchestration to be healthy:
docker-compose ps
```

### 2. Run the Axum app

```bash
cd examples/axum-app
cargo run
```

### 3. Test the endpoints

```bash
# Create an order
curl -X POST http://localhost:3000/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_email":"test@example.com","cart_items":[{"sku":"1","name":"Widget A","quantity":1,"unit_price":29.99}],"payment_token":"tok_test_success","shipping_address":{"street":"123 Main","city":"Portland","state":"OR","zip":"97201","country":"US"}}'

# Check order status
curl http://localhost:3000/orders/1
```

### 4. Run integration tests

```bash
# With the app running in another terminal:
cd examples/axum-app
cargo test
```

## Configuration

| File | Purpose |
|------|---------|
| `.env` | Environment variables (database URLs, Tasker config paths) |
| `config/worker.toml` | Tasker worker configuration (web/gRPC disabled) |
| `config/templates/*.yaml` | Task template definitions for all 4 workflows |
| `migrations/` | Application-specific database schema |

## Dependencies

| Crate | Version | Purpose |
|-------|---------|---------|
| `axum` | 0.7 | HTTP framework |
| `sqlx` | 0.8 | PostgreSQL async driver |
| `tasker-worker` | 0.1.1 | Tasker worker runtime |
| `tasker-client` | 0.1.1 | Tasker orchestration API client |
| `tokio` | 1 | Async runtime |
| `serde` | 1 | Serialization |
| `tower-http` | 0.5 | HTTP middleware (CORS, tracing) |

## Handler Reference

| Handler | Workflow | Step |
|---------|----------|------|
| `ecommerce_validate_cart` | E-commerce | 1/5 |
| `ecommerce_process_payment` | E-commerce | 2/5 |
| `ecommerce_update_inventory` | E-commerce | 3/5 |
| `ecommerce_create_order` | E-commerce | 4/5 |
| `ecommerce_send_confirmation` | E-commerce | 5/5 |
| `data_pipeline_extract_sales` | Analytics | 1/8 |
| `data_pipeline_extract_inventory` | Analytics | 2/8 |
| `data_pipeline_extract_customers` | Analytics | 3/8 |
| `data_pipeline_transform_sales` | Analytics | 4/8 |
| `data_pipeline_transform_inventory` | Analytics | 5/8 |
| `data_pipeline_transform_customers` | Analytics | 6/8 |
| `data_pipeline_aggregate_metrics` | Analytics | 7/8 |
| `data_pipeline_generate_insights` | Analytics | 8/8 |
| `microservices_create_user_account` | Registration | 1/5 |
| `microservices_setup_billing_profile` | Registration | 2/5 |
| `microservices_initialize_preferences` | Registration | 3/5 |
| `microservices_send_welcome_sequence` | Registration | 4/5 |
| `microservices_update_user_status` | Registration | 5/5 |
| `team_scaling_cs_validate_refund_request` | Customer Success | 1/5 |
| `team_scaling_cs_check_refund_policy` | Customer Success | 2/5 |
| `team_scaling_cs_get_manager_approval` | Customer Success | 3/5 |
| `team_scaling_cs_execute_refund_workflow` | Customer Success | 4/5 |
| `team_scaling_cs_update_ticket_status` | Customer Success | 5/5 |
| `team_scaling_payments_validate_eligibility` | Payments | 1/4 |
| `team_scaling_payments_process_gateway_refund` | Payments | 2/4 |
| `team_scaling_payments_update_records` | Payments | 3/4 |
| `team_scaling_payments_notify_customer` | Payments | 4/4 |
