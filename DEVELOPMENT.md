# Development Guide

Local development setup for tasker-contrib — CLI plugin templates and example applications.

---

## Prerequisites

- [cargo-make](https://github.com/sagiegurari/cargo-make) (`cargo install cargo-make`)
- Docker and Docker Compose (for example app testing)
- Language toolchains for the areas you're working on:

| Area | Requirements |
|------|-------------|
| CLI plugin templates | `tasker-ctl` binary (build from tasker-core or `cargo install tasker-ctl`) |
| Rails templates | Ruby 3.3+, Bundler |
| Python templates | Python 3.12+, PyYAML |
| TypeScript templates | Bun 1.0+ |
| Rust templates | Rust stable, rustfmt |
| Ops templates | Python 3.12+, PyYAML |
| Example apps | All of the above + Docker Compose |

---

## Repository Layout

```
tasker-contrib/
├── rails/tasker-cli-plugin/     # Rails CLI plugin (templates + manifest)
├── python/tasker-cli-plugin/    # Python CLI plugin
├── typescript/tasker-cli-plugin/# TypeScript CLI plugin
├── rust/tasker-cli-plugin/      # Rust CLI plugin
├── ops/tasker-cli-plugin/       # Ops CLI plugin (Docker, config)
├── examples/                    # Example applications
│   ├── axum-app/                # Rust (Axum)
│   ├── bun-app/                 # TypeScript (Hono/Bun)
│   ├── fastapi-app/             # Python (FastAPI)
│   ├── rails-app/               # Ruby (Rails)
│   ├── orchestration/           # Shared orchestration config
│   ├── docker-compose.yml       # Shared infrastructure
│   └── init-db.sql              # App database creation
├── scripts/                     # Validation and CI scripts
├── config/                      # Shared Tasker TOML configuration
├── Makefile.toml                # cargo-make task definitions
└── .tasker-cli.toml             # Plugin discovery config
```

Recommended sibling directory layout:

```
tasker-systems/
├── tasker-core/        # Core orchestration engine (for building tasker-ctl locally)
└── tasker-contrib/     # This repository
```

---

## Quick Reference

```bash
cargo make validate          # (v)  Validate all plugin manifests
cargo make test-templates    # (tt) Generate + syntax-check all templates
cargo make test-all          # (ta) validate + test-templates
cargo make ci-sanity-check   # (csc) Validate scripts and workflows
cargo make ci-check          #      All quality checks + CI sanity

# Example app integration tests (require docker-compose services)
cargo make test-examples     # (te) Run all example app tests
cargo make test-example-axum
cargo make test-example-bun
cargo make test-example-fastapi
cargo make test-example-rails
```

---

## Working on CLI Plugin Templates

### Getting tasker-ctl

You need the `tasker-ctl` binary to validate plugins and generate templates.

**Option A: Install from crates.io** (simplest)
```bash
cargo install tasker-ctl
```

**Option B: Build from local tasker-core**
```bash
cargo make build-ctl
# Requires TASKER_CORE_PATH (defaults to ../tasker-core)
```

Either way, the binary ends up discoverable by the Makefile.toml tasks.

### Validating plugins

```bash
# Validate all five plugin manifests
cargo make validate

# Test template generation + syntax checking for all plugins
cargo make test-templates

# Or validate a specific plugin
TASKER_CTL=./bin/tasker-ctl ./scripts/test-templates.sh --plugin tasker-contrib-rails
```

### Template structure

Each plugin follows this structure:

```
{language}/tasker-cli-plugin/
├── tasker-plugin.toml              # Plugin manifest
└── templates/
    ├── step_handler/               # Template directory
    │   ├── template.toml           # Template metadata
    │   └── files/                  # Template files (with Tera syntax)
    ├── step_handler_api/
    ├── step_handler_decision/
    ├── step_handler_batchable/
    └── task_template/
```

---

## Working on Example Applications

The example apps are standalone applications that use published Tasker packages. They share a docker-compose infrastructure stack.

### Starting infrastructure

```bash
cd examples
docker compose up -d
```

This starts:

| Service | Port | Purpose |
|---------|------|---------|
| `tasker-postgres` | 5432 | PostgreSQL 18 + PGMQ + app databases |
| `tasker-orchestration` | 8080 | Tasker orchestration server (GHCR image) |
| `dragonfly` | 6379/11211 | Redis/Memcached cache |
| `rabbitmq` | 5672/15672 | Message broker |

The `init-db.sql` script creates four app databases: `example_axum`, `example_bun`, `example_fastapi`, `example_rails`.

Wait for orchestration to be healthy before running tests:

```bash
curl -sf http://localhost:8080/health
```

### Environment variables

All apps need these shared variables (set in your shell or `.env`):

```bash
export DATABASE_URL=postgresql://tasker:tasker@localhost:5432/tasker
export RABBITMQ_URL=amqp://tasker:tasker@localhost:5672/%2F
export ORCHESTRATION_URL=http://localhost:8080
export TASKER_API_KEY=test-api-key-full-access
export TASKER_ENV=development
export RUST_LOG=info
```

Each app also needs its own `APP_DATABASE_URL` and config paths — see per-app sections below.

### FastAPI app

```bash
cd examples/fastapi-app

export APP_DATABASE_URL=postgresql+asyncpg://tasker:tasker@localhost:5432/example_fastapi
export TASKER_CONFIG_PATH=app/config/worker.toml
export TASKER_TEMPLATE_PATH=app/config/templates

# Install dependencies
uv sync

# Run migrations
APP_DATABASE_URL=postgresql://tasker:tasker@localhost:5432/example_fastapi \
  uv run alembic upgrade head

# Run tests
uv run pytest tests/ -v
```

Note: Alembic migrations need the non-async `APP_DATABASE_URL` (no `+asyncpg`), while the app itself uses the async variant.

### Bun app

```bash
cd examples/bun-app

export APP_DATABASE_URL=postgresql://tasker:tasker@localhost:5432/example_bun
export TASKER_CONFIG_PATH=src/config/worker.toml
export TASKER_TEMPLATE_PATH=src/config/templates

# Install dependencies
bun install

# Run migrations (Drizzle Kit)
bun run db:migrate

# Run tests
bun test tests/
```

### Rails app

```bash
cd examples/rails-app

export APP_DATABASE_URL=postgresql://tasker:tasker@localhost:5432/example_rails
export TASKER_CONFIG_PATH=config/tasker/worker.toml
export TASKER_TEMPLATE_PATH=config/tasker/templates
export RAILS_ENV=test

# Install dependencies
bundle install

# Run migrations
bundle exec rake db:migrate

# Run tests
bundle exec rspec spec/integration/ --format documentation
```

Important: The Rails worker starts once at boot via an initializer. Tests must not re-initialize it — doing so corrupts the FFI bridge.

### Axum app

```bash
cd examples/axum-app

export APP_DATABASE_URL=postgresql://tasker:tasker@localhost:5432/example_axum
export TASKER_CONFIG_PATH=config/worker.toml
export TASKER_TEMPLATE_PATH=config/templates

# Run tests (migrations run automatically via sqlx)
cargo nextest run
```

The Axum app boots an in-process test server and Tasker worker — no separate server process needed.

### Running all example tests at once

```bash
# From repo root (requires docker-compose services running)
cargo make test-examples
```

### Stopping infrastructure

```bash
cd examples
docker compose down -v
```

---

## CI Workflows

| Workflow | Trigger | What It Does |
|----------|---------|--------------|
| **CI** | Push/PR to main | Install `tasker-ctl` from crates.io, validate plugins, generate + syntax-check templates |
| **Test Examples** | `examples/**` changes | Integration tests for all four apps against docker-compose |
| **Upstream Check** | Daily 6 AM UTC | Monitor for new tasker-core releases, create GitHub issues |

See [.github/CI-ARCHITECTURE.md](.github/CI-ARCHITECTURE.md) for full architecture details.

---

## Troubleshooting

### "tasker-ctl not found"

```bash
# Install from crates.io
cargo install tasker-ctl

# Or build from local tasker-core
cargo make build-ctl
```

### Docker compose services won't start

```bash
# Check service status
cd examples && docker compose ps

# View logs
docker compose logs tasker-orchestration
docker compose logs tasker-postgres

# Nuclear reset
docker compose down -v && docker compose up -d
```

### Orchestration not healthy

The orchestration service depends on PostgreSQL and RabbitMQ being fully ready. Wait up to 60 seconds:

```bash
for i in $(seq 1 60); do
  curl -sf http://localhost:8080/health && echo " healthy" && break
  sleep 1
done
```

### "Database does not exist" errors

The `init-db.sql` script creates app databases on first PostgreSQL startup. If you've already created the postgres volume without the init script:

```bash
cd examples
docker compose down -v   # Remove volumes
docker compose up -d     # Recreate with init-db.sql
```

### FFI library load errors (Rails/FastAPI/Bun apps)

The example apps use published FFI packages from their respective registries. If you see library load errors, ensure the correct package versions are installed:

```bash
# Ruby
gem list tasker-core-rb

# Python
pip show tasker-py

# TypeScript
bun pm ls | grep tasker
```

---

## Contributing

### Adding a new template

1. Create template directory: `{language}/tasker-cli-plugin/templates/{template_name}/`
2. Add `template.toml` with metadata and variable definitions
3. Add template files in `files/` subdirectory using Tera syntax
4. Register the template in `tasker-plugin.toml`
5. Run `cargo make test-templates` to verify

### Adding a new example app

1. Create `examples/{framework}-app/` with standard project structure
2. Add the app database to `examples/init-db.sql`
3. Add a `cargo make test-example-{framework}` task to `Makefile.toml`
4. Add the app to `test-examples` dependencies in `Makefile.toml`
5. Add CI steps to `.github/workflows/test-examples.yml`

### Code style

- **Ruby**: Standard Rails conventions
- **Python**: Ruff formatting
- **TypeScript**: Biome
- **Rust**: rustfmt + Clippy
- **Shell**: shellcheck-clean
