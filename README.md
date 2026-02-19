# Tasker Contrib

**CLI plugin templates, example applications, and operational tooling for [Tasker Core](https://github.com/tasker-systems/tasker-core)**

---

## What's Here

Tasker Contrib provides two things:

1. **CLI plugin templates** — code generators for `tasker-ctl` that scaffold step handlers, task definitions, and infrastructure configs across five languages/targets
2. **Example applications** — four fully working apps (one per SDK language) that demonstrate real-world Tasker workflow patterns against published packages

```
tasker-contrib/
├── rails/tasker-cli-plugin/        # Ruby/Rails templates
├── python/tasker-cli-plugin/       # Python templates
├── typescript/tasker-cli-plugin/   # TypeScript templates
├── rust/tasker-cli-plugin/         # Rust templates
├── ops/tasker-cli-plugin/          # Infrastructure templates (Docker, config)
│
├── examples/                       # Example applications
│   ├── axum-app/                   # Rust (Axum) — tasker-worker + tasker-client
│   ├── bun-app/                    # TypeScript (Hono/Bun) — @tasker-systems/tasker
│   ├── fastapi-app/                # Python (FastAPI) — tasker-py
│   ├── rails-app/                  # Ruby (Rails) — tasker-core-rb
│   ├── orchestration/              # Shared orchestration config
│   ├── docker-compose.yml          # Shared infrastructure stack
│   └── init-db.sql                 # Per-app database creation
│
├── scripts/                        # CI and validation scripts
├── config/                         # Shared Tasker configuration
└── docs/                           # Architecture and ticket specs
```

---

## CLI Plugin Templates

Each plugin provides templates for `tasker-ctl template generate`:

| Plugin | Language | Templates |
|--------|----------|-----------|
| `tasker-contrib-rails` | Ruby | step_handler, step_handler_api, step_handler_decision, step_handler_batchable, task_template |
| `tasker-contrib-python` | Python | step_handler, step_handler_api, step_handler_decision, step_handler_batchable, task_template |
| `tasker-contrib-typescript` | TypeScript | step_handler, step_handler_api, step_handler_decision, step_handler_batchable, task_template |
| `tasker-contrib-rust` | Rust | step_handler, task_template |
| `tasker-contrib-ops` | Ops | docker_compose |

```bash
# List available templates
tasker-ctl template list

# Generate a step handler
tasker-ctl template generate step_handler --plugin tasker-contrib-rails --param name=ProcessPayment
```

---

## Example Applications

Four example apps demonstrate the same five workflow patterns using each SDK's idiomatic style:

| App | Framework | SDK Package | Database |
|-----|-----------|-------------|----------|
| `axum-app` | Axum (Rust) | tasker-worker 0.1.4 | `example_axum` |
| `bun-app` | Hono (Bun) | @tasker-systems/tasker 0.1.4 | `example_bun` |
| `fastapi-app` | FastAPI (Python) | tasker-py 0.1.4 | `example_fastapi` |
| `rails-app` | Rails (Ruby) | tasker-core-rb 0.1.4 | `example_rails` |

### Workflow Patterns

All four apps implement these workflows:

1. **E-commerce Order Processing** — multi-step order fulfillment with inventory, payment, shipping
2. **Data Pipeline Analytics** — ETL-style data ingestion, transformation, aggregation
3. **Microservices Orchestration** — cross-service coordination with user provisioning
4. **Customer Success Refund** — refund processing with verification and notification
5. **Payments Compliance** — payment validation with compliance checks

### Running Locally

```bash
# Start shared infrastructure (PostgreSQL + PGMQ, orchestration, RabbitMQ, Dragonfly)
cd examples
docker compose up -d

# Wait for orchestration to be healthy
curl -sf http://localhost:8080/health

# Run any app's tests (see DEVELOPMENT.md for per-app setup)
cd fastapi-app && uv sync && uv run pytest tests/ -v
```

---

## Quick Start

```bash
# Install cargo-make
cargo install cargo-make

# Validate all plugin manifests
cargo make validate

# Generate and syntax-check all templates
cargo make test-templates

# Run example app integration tests (requires docker-compose services)
cargo make test-examples
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for full setup instructions.

---

## CI

| Workflow | Purpose |
|----------|---------|
| **CI** (`ci.yml`) | Validate plugin manifests + generate and syntax-check templates |
| **Test Examples** (`test-examples.yml`) | Integration tests for all four example apps |
| **Upstream Check** (`upstream-check.yml`) | Monitor for new tasker-core package releases |

See [.github/CI-ARCHITECTURE.md](.github/CI-ARCHITECTURE.md) for details.

---

## Related Projects

| Project | Description |
|---------|-------------|
| [tasker-core](https://github.com/tasker-systems/tasker-core) | Rust workflow orchestration engine |
| [tasker-book](https://github.com/tasker-systems/tasker-book) | Documentation hub (GitHub Pages) |

---

## Contributing

Framework-specific expertise is especially valuable. Contribution areas:

- Template improvements for languages you know well
- New example app patterns or workflow demonstrations
- Infrastructure templates (Helm, Terraform, monitoring)
- Documentation and tutorials

See [DEVELOPMENT.md](DEVELOPMENT.md) for setup instructions.

---

## License

MIT License — see [LICENSE](LICENSE) for details.
