# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

**tasker-contrib** provides framework integrations, starter templates, and operational tooling for [Tasker Core](https://github.com/tasker-systems/tasker-core). It bridges Tasker Core's framework-agnostic workflow orchestration with familiar framework idioms (Rails, FastAPI, Bun, Axum).

### Directory Structure

```
tasker-contrib/
├── rails/                    # Ruby/Rails integrations
│   ├── tasker-contrib-rails/ # Gem: Railtie, generators, AS::Notifications bridge
│   ├── tasker-cli-plugin/    # CLI plugin: Templates for tasker-cli
│   └── tasker-rails-template/# Template: Production-ready Rails app
├── python/                   # Python integrations
│   ├── tasker-contrib-fastapi/
│   ├── tasker-contrib-django/
│   ├── tasker-cli-plugin/
│   └── tasker-fastapi-template/
├── typescript/               # TypeScript (Bun-focused)
│   ├── tasker-contrib-bun/
│   ├── tasker-cli-plugin/
│   └── tasker-bun-template/
├── rust/                     # Rust integrations
│   ├── tasker-contrib-axum/
│   ├── tasker-cli-plugin/
│   └── tasker-axum-template/
├── ops/                      # Deployment tooling
│   ├── helm/                 # Kubernetes Helm charts
│   ├── terraform/            # AWS, GCP, Azure modules
│   ├── docker/               # Docker Compose configs
│   └── monitoring/           # Grafana, Prometheus, Datadog
└── examples/                 # Standalone example applications
```

## Development Commands

### Rails (tasker-contrib-rails)

```bash
cd rails/tasker-contrib-rails
bundle install                          # Uses local tasker-core-rb via Gemfile path
bundle exec rspec                       # Run tests
bundle exec rspec spec/path/to/test.rb  # Run single test
bundle exec rubocop --parallel          # Lint

# Test generators in dummy app
cd spec/dummy
bundle exec rails generate tasker:install
bundle exec rails generate tasker:step_handler TestHandler
```

### Python (tasker-contrib-fastapi)

```bash
cd python/tasker-contrib-fastapi
uv sync                                 # Install dependencies
uv run pytest                           # Run tests
uv run ruff check .                     # Lint
uv run ruff format --check .            # Format check
```

### TypeScript (tasker-contrib-bun)

```bash
cd typescript/tasker-contrib-bun
bun install                             # Install dependencies
bun test                                # Run tests
bun run lint                            # Lint
bun run build                           # Build
```

### Rust (tasker-contrib-axum)

```bash
cd rust/tasker-contrib-axum
cargo build                             # Build
cargo test                              # Run tests
cargo fmt --check                       # Check formatting
cargo clippy --all-targets -- -D warnings  # Lint
```

### Ops Validation

```bash
# Docker Compose
docker compose -f ops/docker/development/docker-compose.yml config

# Helm (if installed)
helm lint ops/helm/tasker-orchestration/

# Terraform (if installed)
terraform -chdir=ops/terraform/aws init -backend=false
terraform -chdir=ops/terraform/aws validate
```

## Cross-Repository Dependencies

Tasker Contrib packages depend on Tasker Core. During development, use local path dependencies; for releases, use published versions.

### Local Development Strategy

| Language | Local Dev | Release |
|----------|-----------|---------|
| Ruby | `path:` in Gemfile | Version in gemspec |
| Python | `-e` editable install or uv sources | Version in pyproject.toml |
| TypeScript | `file:` in package.json | Version in package.json |
| Rust | `path` in Cargo.toml or `[patch.crates-io]` | Version in Cargo.toml |

### Required Environment Variables

```bash
export DATABASE_URL="postgresql://tasker:tasker@localhost:5432/tasker_contrib_test"
export TASKER_ENV="test"

# Optional
export TASKER_CLI_PATH="../tasker-core/target/release/tasker-cli"
export RUST_LOG="debug"
```

### Initial Setup

```bash
# Clone both repositories
git clone git@github.com:tasker-systems/tasker-core.git
git clone git@github.com:tasker-systems/tasker-contrib.git

# Build tasker-core first
cd tasker-core
cargo build --release
cd workers/ruby && bundle install && bundle exec rake compile
cd ../python && pip install -e .
cd ../typescript && bun install

# Then work in tasker-contrib
cd ../../tasker-contrib
```

## Architecture Principles

1. **Dependency Direction**: Contrib → Core (never vice versa)
2. **Thin Integration, Thick Core**: Contrib translates framework idioms; business logic stays in Core
3. **CLI Plugin Architecture**: `tasker-cli` loads templates from plugins at runtime
4. **Configuration Passthrough**: Translate framework config to Tasker TOML, don't invent new semantics

## CI Strategy

Path-based CI runs only relevant tests when specific directories change:

- `rails/**` → Rails tests (Ruby 3.2/3.3, Rails 7.0-7.2)
- `python/**` → Python tests (Python 3.11/3.12)
- `typescript/**` → TypeScript tests (Bun)
- `rust/**` → Rust tests
- `ops/**` → Docker/Helm/Terraform validation
- `docs/**` → Markdown link checking

### Testing Modes

1. **CI (ci.yml)**: Path-based, runs against pinned dependencies
2. **Bleeding Edge (bleeding-edge.yml)**: Triggered by tasker-core, tests latest main
3. **Upstream Check (upstream-check.yml)**: Daily check for new tasker-core releases

## Current Status

| Package | Status |
|---------|--------|
| tasker-contrib-rails | In Progress |
| tasker-contrib-fastapi | Planned |
| tasker-contrib-bun | Planned |
| tasker-contrib-axum | Planned |
| Helm charts | Planned |
| Terraform modules | Planned |
