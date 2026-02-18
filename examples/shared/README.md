# Tasker Example Applications

Standalone example applications demonstrating Tasker workflow orchestration patterns using real frameworks with framework-native semantics.

## Architecture

Each example app is a **real framework application** that uses tasker-core for workflow orchestration via FFI (or native Rust). The framework's own web server handles HTTP; tasker's built-in web/gRPC servers are disabled.

```
┌─────────────────────────────────────────────────────────┐
│                    Shared Infrastructure                  │
│  PostgreSQL (+ PGMQ)  │  Dragonfly  │  RabbitMQ         │
│  Tasker Orchestration (GHCR image)                       │
└─────────────────────────────────────────────────────────┘
        │                    │                  │
   ┌────┴────┐    ┌─────────┴────┐    ┌───────┴──────┐
   │ Rails   │    │   FastAPI    │    │  Bun/Hono    │   ...
   │ App DB  │    │   App DB     │    │  App DB      │
   │ :3000   │    │   :8000      │    │  :3000       │
   └─────────┘    └──────────────┘    └──────────────┘
```

## Quick Start

### 1. Start shared infrastructure

```bash
cd examples/
docker-compose up -d
```

Wait for the orchestration service to be healthy:

```bash
docker-compose ps
# orchestration should show "healthy"
```

### 2. Run an example app

Each app directory has its own README with setup instructions:

| App | Framework | Language | Directory |
|-----|-----------|----------|-----------|
| Rails | Ruby on Rails (API mode) | Ruby | `rails-app/` |
| FastAPI | FastAPI + SQLAlchemy | Python | `fastapi-app/` |
| Bun/Hono | Hono + Drizzle ORM | TypeScript | `bun-app/` |
| Axum | Axum + SQLx | Rust | `axum-app/` |

### 3. Run integration tests

```bash
# Rails
cd rails-app && bundle exec rspec spec/integration/

# FastAPI
cd fastapi-app && pytest tests/

# Bun
cd bun-app && bun test

# Axum
cd axum-app && cargo test
```

## Workflows Implemented

Each app implements all 4 workflow patterns from the Tasker blog series:

### 1. E-commerce Order Processing (Blog Post 1)
5 sequential steps: ValidateCart -> ProcessPayment -> UpdateInventory -> CreateOrder -> SendConfirmation

### 2. Data Pipeline Analytics (Blog Post 2)
8 steps with DAG pattern: 3 parallel extracts -> 3 transforms -> aggregate -> generate insights

### 3. Microservices User Registration (Blog Post 3)
5 steps with diamond pattern: CreateUser -> (SetupBilling || InitPreferences) -> SendWelcome -> UpdateStatus

### 4. Team Scaling with Namespace Isolation (Blog Post 4)
9 steps across 2 namespaces: CustomerSuccess (5 steps) + Payments (4 steps) with cross-namespace delegation

## Integration Pattern

All apps follow the same pattern:

1. **Bootstrap**: Start tasker worker at app startup (web/gRPC disabled)
2. **Create**: HTTP endpoint creates domain record, then creates tasker task via FFI
3. **Process**: Tasker orchestrates step execution through registered handlers
4. **Query**: HTTP endpoint loads domain record + task status via FFI

## Configuration

Each app uses:
- `config/tasker/worker.toml` — Worker config (extends `shared/tasker-worker.toml` pattern)
- `config/tasker/templates/` — Task template YAML files for the 4 workflows
- `.env` — Environment variables including `TASKER_CONFIG_PATH` and `TASKER_TEMPLATE_PATH`

## Published Package Dependencies

| App | Package | Registry |
|-----|---------|----------|
| Rails | `tasker-rb ~> 0.1.4` | RubyGems |
| FastAPI | `tasker-py >= 0.1.3` | PyPI |
| Bun | `@tasker-systems/tasker ^0.1.4` | npm |
| Axum | `tasker-worker 0.1.3` | crates.io |
