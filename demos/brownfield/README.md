# Brownfield Workflow Extraction Demo

This is a pre-Tasker FastAPI application used to demonstrate the **brownfield workflow extraction** pattern — taking an existing app with service-layer code and orchestrating it with Tasker using AI-assisted MCP tooling.

## What This App Does

A simple e-commerce order processing API with 5 sequential steps:

1. **Validate cart** — check items, calculate totals (subtotal, tax, shipping)
2. **Process payment** — charge the customer via a simulated gateway
3. **Update inventory** — reserve items in the warehouse
4. **Create order** — assemble the final order record
5. **Send confirmation** — email the customer

All 5 steps run synchronously in a single HTTP request. The business logic lives in `app/services/ecommerce.py` as pure functions.

## The Demo

The accompanying [DEMO-SCRIPT.md](DEMO-SCRIPT.md) walks through using an AI agent with Tasker MCP tools to:

1. Analyze the existing service code
2. Discover a hidden parallelism opportunity (payment and inventory are independent)
3. Generate a Tasker workflow template with a proper DAG
4. Validate the data contracts against existing return types
5. Scaffold typed handler wrappers
6. Wire up the orchestrated version

**The code in this directory stays in its pre-Tasker state.** The transformation happens during the demo but is not committed — this directory always represents the "before" picture.

## Prerequisites

- Python 3.11+
- PostgreSQL (or use the shared docker-compose from `examples/`)
- [uv](https://docs.astral.sh/uv/) (recommended) or pip

## Quick Start

```bash
# From the tasker-contrib root, start shared infrastructure
cd examples && docker-compose up -d && cd ..

# Create the demo database
psql -h localhost -U tasker -c "CREATE DATABASE demo_brownfield;"

# Set up the demo app
cd demos/brownfield
cp .env.template .env
uv sync

# Run migrations
uv run alembic upgrade head

# Start the server
uv run uvicorn app.main:app --reload --port 8090
```

## Test It

```bash
# Create an order
curl -s -X POST http://localhost:8090/orders/ \
  -H "Content-Type: application/json" \
  -d '{
    "customer_email": "demo@example.com",
    "items": [
      {"sku": "WIDGET-001", "name": "Blue Widget", "quantity": 2, "unit_price": 29.99},
      {"sku": "GADGET-042", "name": "Red Gadget", "quantity": 1, "unit_price": 49.99}
    ]
  }' | python -m json.tool

# Get an order
curl -s http://localhost:8090/orders/1 | python -m json.tool

# Health check
curl -s http://localhost:8090/health
```

## Project Structure

```
demos/brownfield/
├── app/
│   ├── main.py              # FastAPI app (vanilla, no Tasker)
│   ├── database.py          # Async SQLAlchemy session
│   ├── models.py            # Order model
│   ├── schemas.py           # Request/response schemas
│   ├── routes/
│   │   └── orders.py        # Sequential service calls
│   └── services/
│       ├── types.py          # Pydantic result types
│       └── ecommerce.py      # Business logic (pure functions)
├── alembic/                  # Database migrations
├── DEMO-SCRIPT.md            # Presenter's guide
├── README.md                 # This file
└── pyproject.toml
```
