# Bun + Hono Example App

A Bun + Hono web application demonstrating 4 Tasker workflow orchestration patterns using the `@tasker-systems/tasker` npm package.

## Workflows

### 1. E-commerce Order Processing
5 sequential steps: ValidateCart -> ProcessPayment -> UpdateInventory -> CreateOrder -> SendConfirmation

### 2. Data Pipeline Analytics
8 steps with DAG pattern: 3 parallel extracts -> 3 transforms -> aggregate -> generate insights

### 3. Microservices User Registration
5 steps with diamond pattern: CreateUser -> (SetupBilling || InitPreferences) -> SendWelcome -> UpdateStatus

### 4. Team Scaling with Namespace Isolation
9 steps across 2 namespaces:
- **customer_success** (5 steps): ValidateRefundRequest -> CheckEligibility -> CalculateAmount -> NotifyCS -> UpdateCRM
- **payments** (4 steps): ProcessRefundPayment -> UpdateLedger -> ReconcileAccount -> GenerateReceipt

## Prerequisites

- [Bun](https://bun.sh/) v1.1+
- Shared infrastructure running (see `examples/docker-compose.yml`)

## Setup

### 1. Start shared infrastructure

```bash
cd examples/
docker-compose up -d
# Wait for orchestration service to be healthy
docker-compose ps
```

### 2. Install dependencies

```bash
cd bun-app/
bun install
```

### 3. Run database migrations

```bash
bun run db:migrate
```

### 4. Start the app

```bash
bun run dev
```

The app starts at http://localhost:3000.

## API Endpoints

### Orders (E-commerce workflow)

```bash
# Create an order (triggers 5-step workflow)
curl -X POST http://localhost:3000/orders \
  -H 'Content-Type: application/json' \
  -d '{
    "customer_email": "alice@example.com",
    "items": [
      {"sku": "WIDGET-001", "name": "Widget", "price": 29.99, "quantity": 2},
      {"sku": "GADGET-002", "name": "Gadget", "price": 49.99, "quantity": 1}
    ],
    "payment_info": {"method": "credit_card", "card_last_four": "4242"}
  }'

# Get order with task status
curl http://localhost:3000/orders/1
```

### Analytics Jobs (Data pipeline workflow)

```bash
# Create analytics job (triggers 8-step DAG pipeline)
curl -X POST http://localhost:3000/analytics/jobs \
  -H 'Content-Type: application/json' \
  -d '{
    "job_name": "Monthly Revenue Analysis",
    "sources": ["sales_db", "inventory_api", "crm_export"],
    "parameters": {"date_start": "2024-01-01", "date_end": "2024-01-31"}
  }'

# Get job with task status
curl http://localhost:3000/analytics/jobs/1
```

### Service Requests (Microservices workflow)

```bash
# Create user registration (triggers 5-step diamond workflow)
curl -X POST http://localhost:3000/services/requests \
  -H 'Content-Type: application/json' \
  -d '{
    "username": "alice",
    "email": "alice@example.com",
    "plan": "standard",
    "metadata": {"timezone": "America/New_York"}
  }'

# Get request with task status
curl http://localhost:3000/services/requests/1
```

### Compliance Checks (Team scaling workflow)

```bash
# Create compliance check (triggers 2 cross-namespace tasks: 5 + 4 steps)
curl -X POST http://localhost:3000/compliance/checks \
  -H 'Content-Type: application/json' \
  -d '{
    "check_type": "refund",
    "entity_type": "order",
    "entity_id": "ORD-12345",
    "parameters": {
      "customer_email": "alice@example.com",
      "order_id": "ORD-12345",
      "reason": "defective_product",
      "refund_amount": "149.99",
      "payment_method": "credit_card",
      "transaction_id": "txn_abc123"
    }
  }'

# Get check with task status
curl http://localhost:3000/compliance/checks/1
```

## Running Tests

```bash
# Start the app first
bun run dev &

# Run integration tests
bun test
```

## Architecture

```
POST /orders
  -> Insert into app DB (orders table)
  -> Create Tasker task via FFI (client_create_task)
  -> Tasker orchestrates: ValidateCart -> ProcessPayment -> ... -> SendConfirmation
  -> Each step handler processes via @tasker-systems/tasker StepHandler

GET /orders/:id
  -> Load from app DB
  -> Fetch task status via FFI (client_get_task)
  -> Return combined domain + workflow view
```

The app uses two separate databases:
- **Tasker DB** (`DATABASE_URL`): Internal orchestration state, steps, queues
- **App DB** (`APP_DATABASE_URL`): Domain models (orders, analytics_jobs, etc.)

## Configuration

- `src/config/worker.toml` -- Worker configuration (web/gRPC disabled, orchestration client settings)
- `src/config/templates/*.yaml` -- Task template definitions for all 4 workflow patterns
- `.env` -- Environment variables for database connections and Tasker paths
