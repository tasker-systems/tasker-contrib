# FastAPI Example App

A complete FastAPI application demonstrating 4 Tasker workflow orchestration patterns using `tasker-py` (PyPI) for Rust FFI integration.

## Architecture

```
FastAPI (uvicorn :8000)        Tasker Orchestration (:8080)
┌──────────────────────┐       ┌───────────────────────┐
│  Routes (HTTP API)   │       │  PostgreSQL + PGMQ    │
│  ├── /orders/        │──────>│  Task state machine   │
│  ├── /analytics/     │ REST  │  Step DAG execution   │
│  ├── /services/      │       │  Event dispatch       │
│  └── /compliance/    │       └───────────────────────┘
│                      │                │
│  Handlers (FFI)      │<───────────────┘
│  ├── ecommerce       │  Step events via
│  ├── data_pipeline   │  FFI dispatch channel
│  ├── microservices   │
│  ├── customer_success│
│  └── payments        │
└──────────────────────┘
```

## Workflow Patterns

### 1. E-commerce Order Processing (Sequential)

5 steps: `ValidateCart -> ProcessPayment -> UpdateInventory -> CreateOrder -> SendConfirmation`

```bash
curl -X POST http://localhost:8000/orders/ \
  -H "Content-Type: application/json" \
  -d '{
    "customer_email": "jane@example.com",
    "items": [{"sku": "WIDGET-001", "name": "Widget", "quantity": 2, "unit_price": 29.99}],
    "payment_token": "tok_test_success"
  }'
```

### 2. Data Pipeline Analytics (DAG)

8 steps: 3 parallel extracts -> 3 transforms -> aggregate -> insights

```bash
curl -X POST http://localhost:8000/analytics/jobs/ \
  -H "Content-Type: application/json" \
  -d '{
    "source": "web_traffic",
    "date_range_start": "2026-01-01",
    "date_range_end": "2026-01-31",
    "granularity": "daily"
  }'
```

### 3. Microservices User Registration (Diamond)

5 steps: `CreateUser -> (SetupBilling || InitPreferences) -> SendWelcome -> UpdateStatus`

```bash
curl -X POST http://localhost:8000/services/requests/ \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "usr_001",
    "email": "newuser@example.com",
    "full_name": "Jane Doe",
    "plan": "professional"
  }'
```

### 4. Team Scaling with Namespace Isolation

9 steps across 2 namespaces: CustomerSuccess (5 steps) + Payments (4 steps)

```bash
# Customer Success namespace
curl -X POST http://localhost:8000/compliance/checks/ \
  -H "Content-Type: application/json" \
  -d '{
    "order_ref": "ORD-ABC123",
    "namespace": "customer_success",
    "reason": "defective_product",
    "amount": 75.50,
    "customer_email": "refund@example.com"
  }'

# Payments namespace
curl -X POST http://localhost:8000/compliance/checks/ \
  -H "Content-Type: application/json" \
  -d '{
    "order_ref": "ORD-XYZ789",
    "namespace": "payments",
    "reason": "duplicate_charge",
    "amount": 199.99,
    "customer_email": "billing@example.com"
  }'
```

## Quick Start

### Prerequisites

- Python 3.11+
- PostgreSQL with PGMQ (via `docker-compose` in `examples/`)
- Tasker orchestration service running on `:8080`

### 1. Start shared infrastructure

```bash
cd examples/
docker-compose up -d
# Wait for orchestration to be healthy:
docker-compose ps
```

### 2. Install dependencies

```bash
cd examples/fastapi-app/
pip install -e ".[dev]"
```

### 3. Run database migrations

```bash
APP_DATABASE_URL=postgresql://tasker:tasker@localhost:5432/example_fastapi \
  alembic upgrade head
```

### 4. Start the app

```bash
uvicorn app.main:app --reload --port 8000
```

### 5. Run tests

```bash
pytest tests/ -v
```

## Project Structure

```
fastapi-app/
├── .env                          # Environment variables
├── pyproject.toml                # Python packaging and dependencies
├── alembic.ini                   # Alembic migration config
├── alembic/
│   ├── env.py                    # Migration environment
│   └── versions/
│       └── 001_create_domain_models.py
├── app/
│   ├── main.py                   # FastAPI app with tasker lifespan
│   ├── database.py               # AsyncSession setup (app DB)
│   ├── models.py                 # SQLAlchemy 2.0 domain models
│   ├── schemas.py                # Pydantic v2 request/response schemas
│   ├── config/
│   │   ├── worker.toml           # Tasker worker configuration
│   │   └── templates/            # Task template YAML files
│   │       ├── ecommerce_order_processing.yaml
│   │       ├── analytics_pipeline.yaml
│   │       ├── user_registration.yaml
│   │       ├── customer_success_process_refund.yaml
│   │       └── payments_process_refund.yaml
│   ├── routes/                   # HTTP endpoint handlers
│   │   ├── orders.py
│   │   ├── analytics.py
│   │   ├── services.py
│   │   └── compliance.py
│   └── handlers/                 # Tasker step handlers
│       ├── ecommerce.py          # 5 handlers
│       ├── data_pipeline.py      # 8 handlers
│       ├── microservices.py      # 5 handlers
│       ├── customer_success.py   # 5 handlers
│       └── payments.py           # 4 handlers
└── tests/
    ├── conftest.py               # Fixtures (worker, client, db)
    └── test_workflows.py         # Integration tests
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `postgresql://tasker:tasker@localhost:5432/tasker` | Tasker internal database |
| `APP_DATABASE_URL` | `postgresql://tasker:tasker@localhost:5432/example_fastapi` | App domain database |
| `TASKER_CONFIG_PATH` | `app/config` | Path to worker.toml |
| `TASKER_TEMPLATE_PATH` | `app/config/templates` | Path to task YAML templates |
| `TASKER_ENV` | `development` | Environment name |

## Integration Pattern

All routes follow the same pattern:

1. **Create**: POST endpoint creates a domain record in the app database, then calls `client_create_task()` via FFI to start a Tasker workflow
2. **Process**: The tasker worker (bootstrapped at app startup) receives step events and dispatches them to the registered Python handlers
3. **Query**: GET endpoint loads the domain record and, if a `task_uuid` is present, fetches the current task status from the orchestration API via `client_get_task()`
