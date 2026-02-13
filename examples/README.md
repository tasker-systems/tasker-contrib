# Tasker Example Applications

Standalone example applications demonstrating Tasker workflow orchestration patterns using real frameworks with framework-native semantics.

## Examples

| Example | Framework | Language | Description |
|---------|-----------|----------|-------------|
| [`rails-app/`](rails-app/) | Ruby on Rails (API mode) | Ruby | ActiveRecord models, Rails controllers, RSpec tests |
| [`fastapi-app/`](fastapi-app/) | FastAPI + SQLAlchemy | Python | Async routes, Alembic migrations, pytest tests |
| [`bun-app/`](bun-app/) | Hono + Drizzle ORM | TypeScript | Bun runtime, Drizzle schema, bun:test integration |
| [`axum-app/`](axum-app/) | Axum + SQLx | Rust | Native async, SQLx migrations, tokio::test integration |

## Workflows

Each app implements all 4 workflow patterns from the Tasker blog series:

1. **E-commerce Order Processing** (5 linear steps) - ValidateCart -> ProcessPayment -> UpdateInventory -> CreateOrder -> SendConfirmation
2. **Data Pipeline Analytics** (8 steps, DAG) - 3 parallel extracts -> 3 transforms -> aggregate -> insights
3. **Microservices User Registration** (5 steps, diamond) - CreateUser -> (Billing || Preferences) -> Welcome -> UpdateStatus
4. **Team Scaling with Namespaces** (9 steps, 2 namespaces) - CustomerSuccess (5) + Payments (4)

## Quick Start

```bash
# 1. Start shared infrastructure
docker-compose up -d

# 2. Pick an example and follow its README
cd rails-app/    # or fastapi-app/, bun-app/, axum-app/
```

## Architecture

Each app is a real framework application that uses tasker-core for workflow orchestration. The framework's web server is primary; tasker's built-in web/gRPC servers are disabled.

```
Shared Infrastructure (docker-compose.yml)
├── PostgreSQL (+ PGMQ extension)
├── Tasker Orchestration (GHCR image)
├── Dragonfly (Redis-compatible cache)
└── RabbitMQ (optional messaging)

Example Apps (each has its own database)
├── rails-app    → example_rails DB   → port 3000
├── fastapi-app  → example_fastapi DB → port 8000
├── bun-app      → example_bun DB     → port 3000
└── axum-app     → example_axum DB    → port 3000
```

## Integration Pattern

All apps follow the same pattern:

1. **Bootstrap** - Start tasker worker at app startup (web/gRPC disabled)
2. **Create** - HTTP POST creates domain record, then creates tasker task via FFI client
3. **Process** - Tasker orchestration dispatches steps to registered handlers
4. **Query** - HTTP GET loads domain record + queries task status via FFI client

## See Also

- [Shared infrastructure setup](shared/README.md)
- [Tasker Core documentation](https://github.com/tasker-systems/tasker-core)
