# Rails API Example - Tasker Workflow Patterns

A minimal Rails 7.1 API-mode application demonstrating four Tasker workflow patterns using the `tasker-rb` gem for FFI-based step handler execution.

## Workflow Patterns

### 1. E-commerce Order Processing (Linear Pipeline)

Five steps executed sequentially, with `process_payment` and `update_inventory` both depending on `validate_cart`, then converging at `create_order`.

```
validate_cart -> process_payment --|
                                   +--> create_order -> send_confirmation
validate_cart -> update_inventory -|
```

**Endpoint:** `POST /orders`

### 2. Analytics Data Pipeline (DAG with Parallel Branches)

Eight steps in a directed acyclic graph. Three extract steps run in parallel, each feeds into its own transform step, then all transforms converge into aggregation and insight generation.

```
extract_sales -----> transform_sales ---------|
extract_inventory -> transform_inventory -----+--> aggregate_metrics -> generate_insights
extract_customers -> transform_customers -----|
```

**Endpoint:** `POST /analytics/jobs`

### 3. User Registration (Diamond Dependency)

Five steps with a diamond pattern. Account creation fans out to billing and preferences setup (parallel), which converge at welcome sequence, then finalize with status update.

```
create_user_account -> setup_billing_profile --------|
                    -> initialize_preferences --------+--> send_welcome_sequence -> update_user_status
```

**Endpoint:** `POST /services/requests`

### 4. Team-Scaling Refund Workflows (Multi-Namespace)

Two separate namespaces handle the same business domain (refunds) with different team-owned workflows:

**Customer Success** (5 steps): `POST /compliance/checks` with `namespace: customer_success`
```
validate_refund_request -> check_refund_policy -> get_manager_approval -> execute_refund_workflow -> update_ticket_status
```

**Payments** (4 steps): `POST /compliance/checks` with `namespace: payments`
```
validate_payment_eligibility -> process_gateway_refund -> update_payment_records -> notify_customer
```

## Prerequisites

- Ruby >= 3.1
- PostgreSQL (via the shared `examples/docker-compose.yml`)
- Tasker orchestration service running on `localhost:8080`

## Setup

```bash
# Start shared infrastructure
cd ../
docker-compose up -d

# Install dependencies
cd rails-app/
bundle install

# Create and migrate the app database
bundle exec rake db:create db:migrate

# Start the Rails server
bundle exec rails server -p 3000
```

## Usage Examples

### Submit an e-commerce order

```bash
curl -X POST http://localhost:3000/orders \
  -H 'Content-Type: application/json' \
  -d '{
    "order": {
      "customer_email": "buyer@example.com",
      "cart_items": [
        {"sku": "SKU-001", "name": "Widget A", "quantity": 2, "unit_price": 29.99}
      ],
      "payment_token": "tok_test_success_4242",
      "shipping_address": {
        "street": "123 Main St", "city": "Portland", "state": "OR", "zip": "97201", "country": "US"
      }
    }
  }'
```

### Submit an analytics pipeline

```bash
curl -X POST http://localhost:3000/analytics/jobs \
  -H 'Content-Type: application/json' \
  -d '{
    "job": {
      "source": "production",
      "date_range": {"start_date": "2026-01-01", "end_date": "2026-01-31"}
    }
  }'
```

### Submit a user registration

```bash
curl -X POST http://localhost:3000/services/requests \
  -H 'Content-Type: application/json' \
  -d '{
    "request": {
      "email": "newuser@example.com",
      "name": "Jane Smith",
      "plan": "pro",
      "referral_code": "REF-ABC12345",
      "marketing_consent": true
    }
  }'
```

### Submit a customer success refund

```bash
curl -X POST http://localhost:3000/compliance/checks \
  -H 'Content-Type: application/json' \
  -d '{
    "check": {
      "namespace": "customer_success",
      "order_ref": "ORD-20260101-ABC123",
      "ticket_id": "TICKET-9001",
      "customer_id": "CUST-12345",
      "refund_amount": 149.99,
      "reason": "defective",
      "agent_id": "agent_42",
      "priority": "high"
    }
  }'
```

### Submit a payments refund

```bash
curl -X POST http://localhost:3000/compliance/checks \
  -H 'Content-Type: application/json' \
  -d '{
    "check": {
      "namespace": "payments",
      "order_ref": "ORD-20260101-DEF456",
      "payment_id": "pay_abc123def456",
      "refund_amount": 75.50,
      "currency": "USD",
      "reason": "duplicate_charge"
    }
  }'
```

### Check status of any resource

```bash
curl http://localhost:3000/orders/<id>
curl http://localhost:3000/analytics/jobs/<id>
curl http://localhost:3000/services/requests/<id>
curl http://localhost:3000/compliance/checks/<id>
```

## Running Tests

```bash
bundle exec rspec spec/integration/workflows_spec.rb --format documentation
```

## Architecture

```
app/
  controllers/     # REST endpoints that create domain records + submit Tasker tasks
  models/          # ActiveRecord models with task_uuid for workflow correlation
  handlers/        # Tasker step handlers organized by workflow domain
    ecommerce/     # 5 handlers for order processing
    data_pipeline/ # 8 handlers for ETL pipeline
    microservices/ # 5 handlers for user registration
    customer_success/ # 5 handlers for CS refund flow
    payments/      # 4 handlers for payments refund flow

config/
  tasker/
    worker.toml        # Tasker worker FFI configuration
    templates/         # Task template YAMLs defining step DAGs
```

Each handler extends `TaskerCore::StepHandler::Base` and implements a `call(context)` method that:
- Reads task inputs via `context.get_input('field')`
- Reads upstream step results via `context.get_dependency_field('step_name', ['field'])`
- Returns `TaskerCore::Types::StepHandlerCallResult.success(result: {...}, metadata: {...})`
- Raises `TaskerCore::Errors::PermanentError` or `TaskerCore::Errors::RetryableError` for failures
