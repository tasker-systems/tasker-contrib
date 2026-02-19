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

### Template Validation (cargo-make)

```bash
# Install cargo-make if needed
cargo install cargo-make

# Build tasker-ctl from sibling tasker-core repo
cargo make build-ctl

# Validate all plugin manifests
cargo make validate                      # or: cargo make v

# Generate + syntax-check all templates
cargo make test-templates                # or: cargo make tt

# Run all validation
cargo make test-all                      # or: cargo make ta
```

### Direct Script Usage

```bash
# Set TASKER_CTL to point at the binary
export TASKER_CTL=../tasker-core/target/debug/tasker-ctl

# Validate plugins
./scripts/validate-plugins.sh

# Test all templates
./scripts/test-templates.sh

# Test a single plugin
./scripts/test-templates.sh --plugin tasker-contrib-rails
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

Template validation CI builds `tasker-ctl` from tasker-core source and validates all plugin templates:

- `rails/tasker-cli-plugin/**` → Generate Rails templates, `ruby -c` syntax check
- `python/tasker-cli-plugin/**` → Generate Python templates, `py_compile` check
- `typescript/tasker-cli-plugin/**` → Generate TypeScript templates, `bun build` check
- `rust/tasker-cli-plugin/**` → Generate Rust templates, `rustfmt --check`
- `ops/tasker-cli-plugin/**` → Generate ops templates, YAML/TOML validation
- `docs/**` → Markdown link checking

### Testing Modes

1. **CI (ci.yml)**: Path-based template validation on PR/merge
2. **Bleeding Edge (bleeding-edge.yml)**: Full validation against latest tasker-core main
3. **Upstream Check (upstream-check.yml)**: Daily registry checks for new tasker-core releases

See [.github/CI-ARCHITECTURE.md](.github/CI-ARCHITECTURE.md) for full details.

## Current Status

| Plugin | Templates | Status |
|--------|-----------|--------|
| tasker-contrib-rails | 4 handlers + task template | Active |
| tasker-contrib-python | 4 handlers + task template | Active |
| tasker-contrib-typescript | 4 handlers + task template | Active |
| tasker-contrib-rust | 1 handler + task template | Active |
| tasker-contrib-ops | docker_compose | Active |
