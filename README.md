# Tasker Contrib

**Framework integrations, starter templates, and operational tooling for [Tasker Core](https://github.com/tasker-systems/tasker-core)**

---

## Vision

Tasker Core provides powerful, framework-agnostic workflow orchestration built on Rust, PostgreSQL, and PGMQ. It solves the hard distributed systems problems: DAG execution, state machines, reliable queueing, cross-language FFI workers.

What Tasker Core intentionally does *not* provide:
- Framework-specific generators (`rails generate`, FastAPI scaffolding)
- Framework lifecycle integration (Rails initializers, FastAPI startup hooks)
- Framework idiom translations (ActiveSupport::Notifications, Pydantic models)
- Deployment templates (Helm charts, Terraform modules)
- Starter application templates

This is by design—Tasker Core must remain framework-agnostic to support its polyglot worker ecosystem.

**Tasker Contrib bridges this gap.**

| Layer | Responsibility |
|-------|----------------|
| **Tasker Core** | Solves the hard distributed systems problems |
| **Tasker Contrib** | Makes those solutions accessible through familiar framework idioms |

---

## Repository Structure

```
tasker-contrib/
├── rails/                      # Rails framework integration
│   ├── tasker-contrib-rails/   # Gem: Railtie, generators, event bridge
│   ├── tasker-cli-plugin/      # CLI plugin: Templates for tasker-cli
│   └── tasker-rails-template/  # Template: Production-ready Rails app
│
├── python/                     # Python framework integrations
│   ├── tasker-contrib-fastapi/ # Package: FastAPI integration
│   ├── tasker-contrib-django/  # Package: Django integration
│   ├── tasker-cli-plugin/      # CLI plugin: Python templates
│   └── tasker-fastapi-template/# Template: Production-ready FastAPI app
│
├── typescript/                 # TypeScript integrations (Bun-focused)
│   ├── tasker-contrib-bun/     # Package: Bun.serve integration
│   ├── tasker-cli-plugin/      # CLI plugin: TypeScript templates
│   └── tasker-bun-template/    # Template: Production-ready Bun app
│
├── rust/                       # Rust framework integrations
│   ├── tasker-contrib-axum/    # Crate: Axum integration
│   ├── tasker-cli-plugin/      # CLI plugin: Rust templates
│   └── tasker-axum-template/   # Template: Production-ready Axum app
│
├── ops/                        # Operational tooling
│   ├── helm/                   # Kubernetes Helm charts
│   │   ├── tasker-orchestration/
│   │   ├── tasker-worker/
│   │   └── tasker-full-stack/
│   ├── terraform/              # Cloud infrastructure modules
│   │   ├── aws/
│   │   ├── gcp/
│   │   └── azure/
│   ├── docker/                 # Docker Compose configurations
│   │   ├── development/
│   │   ├── production/
│   │   └── observability/
│   └── monitoring/             # Observability configurations
│       ├── grafana-dashboards/
│       ├── prometheus-rules/
│       └── datadog-monitors/
│
├── examples/                   # Standalone example applications
│   ├── e-commerce-workflow/
│   ├── etl-pipeline/
│   └── approval-system/
│
└── docs/
    ├── ticket-specs/           # Implementation specifications
    ├── architecture/           # Cross-cutting decisions
    └── guides/                 # User-facing documentation
```

---

## Current Status

| Package | Status | Description |
|---------|--------|-------------|
| `tasker-contrib-rails` | 🚧 In Progress | Rails Railtie, generators, AS::Notifications bridge |
| `tasker-contrib-fastapi` | 📋 Planned | FastAPI startup hooks, Pydantic integration |
| `tasker-contrib-bun` | 📋 Planned | Bun.serve integration, TypeScript handlers |
| `tasker-contrib-axum` | 📋 Planned | Axum layers, state extractors |
| Helm charts | 📋 Planned | Kubernetes deployment charts |
| Terraform modules | 📋 Planned | AWS, GCP, Azure infrastructure |

---

## Architectural Principles

### 1. Dependency Direction: Contrib → Core

Framework bridges depend on Tasker Core packages, never vice versa. This ensures Core remains framework-agnostic.

```
┌─────────────────────────────────────────────────────────────┐
│                    APPLICATION LAYER                         │
│  (Your Rails app, FastAPI service, Bun server, etc.)        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    TASKER CONTRIB LAYER                      │
│  tasker-contrib-rails, tasker-contrib-fastapi, etc.         │
│  - Framework-specific generators                             │
│  - Lifecycle integration (initializers, startup hooks)       │
│  - Event bridges (AS::Notifications, signals)               │
│  - Config DSL wrappers                                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    TASKER CORE LAYER                         │
│  tasker-core-rb, tasker-core-py, tasker-core-ts             │
│  - Handler base classes                                      │
│  - Type definitions                                          │
│  - FFI bridge                                               │
│  - Domain events                                            │
│  - Bootstrap/lifecycle                                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    RUST FOUNDATION                           │
│  tasker-orchestration, tasker-worker                        │
│  - DAG execution engine                                     │
│  - State machines                                           │
│  - PGMQ integration                                         │
│  - Actor system                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2. Thin Integration, Thick Core

Contrib packages should be thin wrappers that translate framework idioms to Tasker Core concepts. Business logic and workflow execution remain in Core.

### 3. CLI as Shared Foundation with Plugin Architecture

The `tasker-cli` (in tasker-core) is a stable binary that loads templates from plugins at runtime. This means:

- **CLI binary doesn't need rebuilding** when templates change
- **Plugins live in tasker-contrib** alongside framework integrations
- **Users can customize** via `.config/tasker-cli.toml` (like nextest)
- **Local development** can point to local plugin paths

```bash
# CLI discovers templates from plugins
tasker-cli template list
# TEMPLATE              PLUGIN                  LANGUAGES
# step-handler          tasker-contrib-rails    ruby
# step-handler          tasker-contrib-python   python
# step-handler          tasker-contrib-typescript typescript

# Generate with framework hint
tasker-cli template generate step-handler \
  --name ProcessPayment \
  --framework rails \
  --output ./app/handlers/

# Framework generators wrap the CLI
rails generate tasker:step_handler ProcessPayment
# Internally calls: tasker-cli template generate ...
```

**Plugin Configuration** (`.config/tasker-cli.toml`):
```toml
[profiles.development]
plugin-paths = [
    "~/projects/tasker-systems/tasker-contrib",
]

[profiles.ci]
use-published-plugins = true
```

See [CLI Plugin Architecture](docs/ticket-specs/TAS-126/cli-plugin-architecture.md) for details.

### 4. Configuration Passthrough

Contrib packages translate framework configuration idioms to Tasker's TOML configuration, but don't invent new configuration semantics.

```ruby
# Rails initializer generates/modifies TOML
Tasker.configure do |config|
  config.database.pool_size = 20  # → worker.toml: [database.pool] max_connections = 20
end
```

### 5. Opt-In Complexity

Start with the simplest possible integration. Advanced features (ActiveJob adapters, complex event bridges) are opt-in and documented separately.

---

## Responsibility Boundaries

### What Belongs in Tasker Core

| Component | Rationale |
|-----------|-----------|
| Handler base classes | FFI-coupled, framework-agnostic |
| Type definitions | Cross-language consistency |
| FFI bridge code | Language-specific but not framework-specific |
| Domain event system | Part of orchestration contract |
| Bootstrap/lifecycle | Core worker concern |
| `tasker-cli` | Shared tooling foundation |
| TOML configuration | Language-agnostic format |

### What Belongs in Tasker Contrib

| Component | Rationale |
|-----------|-----------|
| Framework generators | Rails, FastAPI, etc. specific |
| Lifecycle hooks | Railties, FastAPI lifespan, etc. |
| Config DSL wrappers | Framework idiom translation |
| Event bridges | AS::Notifications, signals, etc. |
| Testing helpers | RSpec matchers, pytest fixtures |
| Application templates | Opinionated starter apps |
| Deployment tooling | Helm, Terraform, Docker Compose |

---

## Getting Started

### Rails

```ruby
# Gemfile
gem 'tasker-contrib-rails'
gem 'tasker-core-rb'
```

```bash
bundle install
rails generate tasker:install
rails generate tasker:step_handler ProcessPayment --type api
```

### FastAPI

```python
# pyproject.toml
dependencies = [
    "tasker-contrib-fastapi",
    "tasker-core-py",
]
```

```bash
pip install -e .
tasker init --framework fastapi
tasker generate handler process_payment --type api
```

### Bun

```bash
bun add tasker-contrib-bun tasker-core-ts
```

```typescript
import { TaskerServer } from 'tasker-contrib-bun';

const server = new TaskerServer({
  port: 3000,
  handlers: './handlers',
});

server.start();
```

---

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for:
- Local development setup
- Cross-repository dependency management
- Testing against local tasker-core builds
- Contributing guidelines

---

## Documentation

| Document | Description |
|----------|-------------|
| [DEVELOPMENT.md](DEVELOPMENT.md) | Local development and cross-repo setup |
| [docs/ticket-specs/](docs/ticket-specs/) | Implementation specifications |
| [TAS-126: Foundations](docs/ticket-specs/TAS-126/) | Foundations and CLI plugin architecture |

---

## Related Projects

| Project | Description |
|---------|-------------|
| [tasker-core](https://github.com/tasker-systems/tasker-core) | Rust-based workflow orchestration engine |
| [tasker-engine](https://github.com/tasker-systems/tasker-engine) | Legacy Rails engine (reference only, never released) |

---

## Contributing

Tasker Contrib is designed to welcome community contributions more readily than Tasker Core. Framework-specific expertise is especially valuable.

**Contribution areas:**
- Framework integrations for languages/frameworks you know well
- Helm charts and Terraform modules for your cloud platform
- Grafana dashboards and monitoring configurations
- Example applications demonstrating real-world patterns
- Documentation improvements and tutorials

See [DEVELOPMENT.md](DEVELOPMENT.md) for setup instructions.

---

## License

MIT License - see [LICENSE](LICENSE) for details.
