#!/bin/bash

# Tasker Contrib Directory Structure Setup Script
# Creates the full directory structure with placeholder files

set -e

REPO_ROOT="/Users/petetaylor/projects/tasker-systems/tasker-contrib"
TASKER_CORE="/Users/petetaylor/projects/tasker-systems/tasker-core"

cd "$REPO_ROOT"

echo "🏗️  Creating Tasker Contrib directory structure..."

# =============================================================================
# Rails
# =============================================================================
echo "📁 Creating rails/ structure..."

mkdir -p rails/tasker-contrib-rails/lib/tasker_contrib_rails/{generators,event_bridge,testing}
mkdir -p rails/tasker-contrib-rails/spec/{generators,event_bridge,dummy}
mkdir -p rails/tasker-cli-plugin/templates/{step_handler,step_handler_api,step_handler_decision,step_handler_batchable,task_template,rails_initializer}
mkdir -p rails/tasker-rails-template

cat > rails/README.md << 'EOF'
# Rails Integration

This directory contains Rails framework integration for Tasker.

## Contents

| Directory | Description |
|-----------|-------------|
| `tasker-contrib-rails/` | Ruby gem with Railtie, generators, and event bridge |
| `tasker-cli-plugin/` | CLI plugin with Ruby/Rails templates for `tasker-cli` |
| `tasker-rails-template/` | Production-ready Rails application template |

## Status

🚧 In Development - See [TAS-126](https://linear.app/tasker-systems/issue/TAS-126)
EOF

cat > rails/tasker-contrib-rails/README.md << 'EOF'
# tasker-contrib-rails

Rails integration gem for Tasker Core.

## Features

- **Railtie** - Initializes tasker-core-rb at Rails boot
- **Generators** - `rails g tasker:install`, `rails g tasker:step_handler`, etc.
- **Event Bridge** - Domain events → ActiveSupport::Notifications
- **Testing Helpers** - RSpec matchers and context builders

## Installation

```ruby
# Gemfile
gem 'tasker-contrib-rails'
gem 'tasker-core-rb'
```

## Status

🚧 In Development
EOF

touch rails/tasker-contrib-rails/lib/tasker_contrib_rails/.keep
touch rails/tasker-contrib-rails/lib/tasker_contrib_rails/generators/.keep
touch rails/tasker-contrib-rails/lib/tasker_contrib_rails/event_bridge/.keep
touch rails/tasker-contrib-rails/lib/tasker_contrib_rails/testing/.keep
touch rails/tasker-contrib-rails/spec/generators/.keep
touch rails/tasker-contrib-rails/spec/event_bridge/.keep
touch rails/tasker-contrib-rails/spec/dummy/.keep

cat > rails/tasker-cli-plugin/README.md << 'EOF'
# Rails CLI Plugin

Templates for `tasker-cli` to generate Ruby/Rails handlers and configurations.

## Structure

```
templates/
├── step_handler/           # Base step handler
├── step_handler_api/       # API handler with HTTP client
├── step_handler_decision/  # Decision handler for conditional workflows
├── step_handler_batchable/ # Batchable handler for large datasets
├── task_template/          # YAML task template
└── rails_initializer/      # Rails initializer template
```

## Usage

These templates are loaded by `tasker-cli` at runtime. Configure plugin discovery:

```toml
# .config/tasker-cli.toml
[profiles.development]
plugin-paths = ["~/projects/tasker-systems/tasker-contrib"]
```

Then generate:

```bash
tasker-cli template generate step-handler --name ProcessPayment --framework rails
```

## Status

🚧 In Development - Depends on TAS-127 (CLI plugin system)
EOF

cat > rails/tasker-cli-plugin/tasker-plugin.toml << 'EOF'
# Tasker CLI Plugin Manifest
# This file tells tasker-cli how to discover and use templates from this plugin

[plugin]
name = "tasker-contrib-rails"
version = "0.1.0"
description = "Rails templates and generators for Tasker CLI"
languages = ["ruby"]
frameworks = ["rails"]

[templates]
step-handler = { path = "templates/step_handler", languages = ["ruby"] }
step-handler-api = { path = "templates/step_handler_api", languages = ["ruby"] }
step-handler-decision = { path = "templates/step_handler_decision", languages = ["ruby"] }
step-handler-batchable = { path = "templates/step_handler_batchable", languages = ["ruby"] }
task-template = { path = "templates/task_template", languages = ["ruby"] }
rails-initializer = { path = "templates/rails_initializer", frameworks = ["rails"] }
EOF

# Add .keep files to template directories
for dir in rails/tasker-cli-plugin/templates/*/; do
  touch "${dir}.keep"
done

cat > rails/tasker-rails-template/README.md << 'EOF'
# Tasker Rails Template

Production-ready Rails application template with Tasker integration.

## Usage

```bash
# Create new Rails app from template
rails new my-tasker-app -m https://raw.githubusercontent.com/tasker-systems/tasker-contrib/main/rails/tasker-rails-template/template.rb
```

## What's Included

- tasker-contrib-rails gem configured
- Example handlers
- Docker Compose for local development
- RSpec test setup
- CI configuration

## Status

📋 Planned
EOF

# =============================================================================
# Python
# =============================================================================
echo "📁 Creating python/ structure..."

mkdir -p python/tasker-contrib-fastapi/src/tasker_contrib_fastapi
mkdir -p python/tasker-contrib-fastapi/tests
mkdir -p python/tasker-contrib-django/src/tasker_contrib_django
mkdir -p python/tasker-contrib-django/tests
mkdir -p python/tasker-cli-plugin/templates/{step_handler,step_handler_api,step_handler_decision,step_handler_batchable,task_template}
mkdir -p python/tasker-fastapi-template

cat > python/README.md << 'EOF'
# Python Integration

This directory contains Python framework integrations for Tasker.

## Contents

| Directory | Description |
|-----------|-------------|
| `tasker-contrib-fastapi/` | FastAPI integration with startup hooks and Pydantic models |
| `tasker-contrib-django/` | Django integration (future) |
| `tasker-cli-plugin/` | CLI plugin with Python templates for `tasker-cli` |
| `tasker-fastapi-template/` | Production-ready FastAPI application template |

## Status

📋 Planned
EOF

cat > python/tasker-contrib-fastapi/README.md << 'EOF'
# tasker-contrib-fastapi

FastAPI integration for Tasker Core.

## Features

- **Lifespan Integration** - Bootstrap tasker-core-py on FastAPI startup
- **Dependency Injection** - Tasker client as FastAPI dependency
- **Pydantic Models** - Type-safe task request/response models
- **Testing Utilities** - pytest fixtures and helpers

## Installation

```bash
pip install tasker-contrib-fastapi tasker-core-py
```

## Status

📋 Planned
EOF

touch python/tasker-contrib-fastapi/src/tasker_contrib_fastapi/.keep
touch python/tasker-contrib-fastapi/tests/.keep

cat > python/tasker-contrib-django/README.md << 'EOF'
# tasker-contrib-django

Django integration for Tasker Core.

## Status

📋 Planned (Future)
EOF

touch python/tasker-contrib-django/src/tasker_contrib_django/.keep
touch python/tasker-contrib-django/tests/.keep

cat > python/tasker-cli-plugin/README.md << 'EOF'
# Python CLI Plugin

Templates for `tasker-cli` to generate Python handlers and configurations.

## Status

📋 Planned - Depends on TAS-127 (CLI plugin system)
EOF

cat > python/tasker-cli-plugin/tasker-plugin.toml << 'EOF'
# Tasker CLI Plugin Manifest

[plugin]
name = "tasker-contrib-python"
version = "0.1.0"
description = "Python templates for Tasker CLI"
languages = ["python"]
frameworks = ["fastapi", "django"]

[templates]
step-handler = { path = "templates/step_handler", languages = ["python"] }
step-handler-api = { path = "templates/step_handler_api", languages = ["python"] }
step-handler-decision = { path = "templates/step_handler_decision", languages = ["python"] }
step-handler-batchable = { path = "templates/step_handler_batchable", languages = ["python"] }
task-template = { path = "templates/task_template", languages = ["python"] }
EOF

for dir in python/tasker-cli-plugin/templates/*/; do
  touch "${dir}.keep"
done

cat > python/tasker-fastapi-template/README.md << 'EOF'
# Tasker FastAPI Template

Production-ready FastAPI application template with Tasker integration.

## Status

📋 Planned
EOF

# =============================================================================
# TypeScript (Bun-focused)
# =============================================================================
echo "📁 Creating typescript/ structure..."

mkdir -p typescript/tasker-contrib-bun/src
mkdir -p typescript/tasker-contrib-bun/tests
mkdir -p typescript/tasker-cli-plugin/templates/{step_handler,step_handler_api,step_handler_decision,step_handler_batchable,task_template}
mkdir -p typescript/tasker-bun-template

cat > typescript/README.md << 'EOF'
# TypeScript Integration

This directory contains TypeScript framework integrations for Tasker.

## Philosophy

We recommend **Bun** for TypeScript Tasker applications. Bun is fast, modern,
batteries-included, and aligns with Tasker's philosophy of powerful simplicity.

## Contents

| Directory | Description |
|-----------|-------------|
| `tasker-contrib-bun/` | Bun integration with `Bun.serve` patterns |
| `tasker-cli-plugin/` | CLI plugin with TypeScript templates for `tasker-cli` |
| `tasker-bun-template/` | Production-ready Bun application template |

## Why Bun?

- **Fast** - Native speed, minimal overhead
- **Modern** - First-class TypeScript, ESM by default
- **Batteries Included** - Built-in test runner, bundler, package manager
- **Simple** - `Bun.serve` is all you need for HTTP

## Status

📋 Planned
EOF

cat > typescript/tasker-contrib-bun/README.md << 'EOF'
# tasker-contrib-bun

Bun integration for Tasker Core.

## Features

- **Bun.serve Integration** - Simple HTTP server with Tasker lifecycle
- **Type Definitions** - Full TypeScript types for Tasker APIs
- **Testing Utilities** - Bun test helpers

## Installation

```bash
bun add tasker-contrib-bun tasker-core-ts
```

## Quick Start

```typescript
import { TaskerServer } from 'tasker-contrib-bun';

const server = new TaskerServer({
  port: 3000,
  handlers: './handlers',
});

server.start();
```

## Status

📋 Planned
EOF

touch typescript/tasker-contrib-bun/src/.keep
touch typescript/tasker-contrib-bun/tests/.keep

cat > typescript/tasker-cli-plugin/README.md << 'EOF'
# TypeScript CLI Plugin

Templates for `tasker-cli` to generate TypeScript handlers and configurations.

## Status

📋 Planned - Depends on TAS-127 (CLI plugin system)
EOF

cat > typescript/tasker-cli-plugin/tasker-plugin.toml << 'EOF'
# Tasker CLI Plugin Manifest

[plugin]
name = "tasker-contrib-typescript"
version = "0.1.0"
description = "TypeScript templates for Tasker CLI"
languages = ["typescript"]
frameworks = ["bun"]

[templates]
step-handler = { path = "templates/step_handler", languages = ["typescript"] }
step-handler-api = { path = "templates/step_handler_api", languages = ["typescript"] }
step-handler-decision = { path = "templates/step_handler_decision", languages = ["typescript"] }
step-handler-batchable = { path = "templates/step_handler_batchable", languages = ["typescript"] }
task-template = { path = "templates/task_template", languages = ["typescript"] }
EOF

for dir in typescript/tasker-cli-plugin/templates/*/; do
  touch "${dir}.keep"
done

cat > typescript/tasker-bun-template/README.md << 'EOF'
# Tasker Bun Template

Production-ready Bun application template with Tasker integration.

## Status

📋 Planned
EOF

# =============================================================================
# Rust
# =============================================================================
echo "📁 Creating rust/ structure..."

mkdir -p rust/tasker-contrib-axum/src
mkdir -p rust/tasker-cli-plugin/templates/{step_handler,task_template}
mkdir -p rust/tasker-axum-template

cat > rust/README.md << 'EOF'
# Rust Integration

This directory contains Rust framework integrations for Tasker.

## Contents

| Directory | Description |
|-----------|-------------|
| `tasker-contrib-axum/` | Axum integration with Tower layers and state extractors |
| `tasker-cli-plugin/` | CLI plugin with Rust templates for `tasker-cli` |
| `tasker-axum-template/` | Production-ready Axum application template |

## Note

For pure Rust applications, consider using `tasker-worker` directly from tasker-core.
This integration is for applications that want Axum-specific conveniences.

## Status

📋 Planned
EOF

cat > rust/tasker-contrib-axum/README.md << 'EOF'
# tasker-contrib-axum

Axum integration for Tasker Core.

## Features

- **State Extractors** - Access Tasker client from handlers
- **Tower Layers** - Middleware for task lifecycle
- **Router Integration** - Mount Tasker routes

## Status

📋 Planned
EOF

touch rust/tasker-contrib-axum/src/.keep

cat > rust/tasker-cli-plugin/README.md << 'EOF'
# Rust CLI Plugin

Templates for `tasker-cli` to generate Rust handlers and configurations.

## Status

📋 Planned - Depends on TAS-127 (CLI plugin system)
EOF

cat > rust/tasker-cli-plugin/tasker-plugin.toml << 'EOF'
# Tasker CLI Plugin Manifest

[plugin]
name = "tasker-contrib-rust"
version = "0.1.0"
description = "Rust templates for Tasker CLI"
languages = ["rust"]
frameworks = ["axum"]

[templates]
step-handler = { path = "templates/step_handler", languages = ["rust"] }
task-template = { path = "templates/task_template", languages = ["rust"] }
EOF

for dir in rust/tasker-cli-plugin/templates/*/; do
  touch "${dir}.keep"
done

cat > rust/tasker-axum-template/README.md << 'EOF'
# Tasker Axum Template

Production-ready Axum application template with Tasker integration.

## Status

📋 Planned
EOF

# =============================================================================
# Ops
# =============================================================================
echo "📁 Creating ops/ structure..."

mkdir -p ops/helm/{tasker-orchestration,tasker-worker,tasker-full-stack}
mkdir -p ops/terraform/{aws,gcp,azure}
mkdir -p ops/docker/{development,production,observability}
mkdir -p ops/monitoring/{grafana-dashboards,prometheus-rules,datadog-monitors}

cat > ops/README.md << 'EOF'
# Operational Tooling

Infrastructure, deployment, and observability configurations for Tasker.

## Contents

| Directory | Description |
|-----------|-------------|
| `helm/` | Kubernetes Helm charts |
| `terraform/` | Cloud infrastructure modules (AWS, GCP, Azure) |
| `docker/` | Docker Compose configurations |
| `monitoring/` | Observability configurations (Grafana, Prometheus, Datadog) |

## Quick Start

### Local Development with Docker

```bash
cd ops/docker/development
docker-compose up -d
```

### Kubernetes with Helm

```bash
helm install tasker ./ops/helm/tasker-full-stack
```

## Status

📋 Planned
EOF

# Helm
cat > ops/helm/README.md << 'EOF'
# Helm Charts

Kubernetes Helm charts for deploying Tasker components.

## Charts

| Chart | Description |
|-------|-------------|
| `tasker-orchestration/` | Orchestration server deployment |
| `tasker-worker/` | Worker deployment (configurable per language) |
| `tasker-full-stack/` | Complete Tasker deployment with PostgreSQL |

## Status

📋 Planned
EOF

touch ops/helm/tasker-orchestration/.keep
touch ops/helm/tasker-worker/.keep
touch ops/helm/tasker-full-stack/.keep

# Terraform
cat > ops/terraform/README.md << 'EOF'
# Terraform Modules

Cloud infrastructure modules for Tasker deployments.

## Modules

| Module | Description |
|--------|-------------|
| `aws/` | AWS infrastructure (RDS, ECS/EKS, VPC) |
| `gcp/` | GCP infrastructure (Cloud SQL, GKE, VPC) |
| `azure/` | Azure infrastructure (PostgreSQL, AKS, VNet) |

## Status

📋 Planned
EOF

touch ops/terraform/aws/.keep
touch ops/terraform/gcp/.keep
touch ops/terraform/azure/.keep

# Docker
cat > ops/docker/README.md << 'EOF'
# Docker Configurations

Docker Compose configurations for local development and testing.

## Environments

| Directory | Description |
|-----------|-------------|
| `development/` | Local development with hot reload |
| `production/` | Production-like configuration |
| `observability/` | Full observability stack (Jaeger, Prometheus, Grafana) |

## Quick Start

```bash
# Development
cd development
docker-compose up -d

# With observability
cd observability
docker-compose up -d
```

## Origin

These configurations are adapted from tasker-core/docker with contrib-specific additions.
EOF

touch ops/docker/development/.keep
touch ops/docker/production/.keep
touch ops/docker/observability/.keep

# Monitoring
cat > ops/monitoring/README.md << 'EOF'
# Monitoring Configurations

Observability configurations for production Tasker deployments.

## Contents

| Directory | Description |
|-----------|-------------|
| `grafana-dashboards/` | Grafana dashboard JSON definitions |
| `prometheus-rules/` | Prometheus alerting rules |
| `datadog-monitors/` | Datadog monitor configurations |

## Status

📋 Planned
EOF

touch ops/monitoring/grafana-dashboards/.keep
touch ops/monitoring/prometheus-rules/.keep
touch ops/monitoring/datadog-monitors/.keep

# =============================================================================
# Examples
# =============================================================================
echo "📁 Creating examples/ structure..."

mkdir -p examples/{e-commerce-workflow,etl-pipeline,approval-system}

cat > examples/README.md << 'EOF'
# Example Applications

Complete example applications demonstrating Tasker patterns.

## Examples

| Example | Description |
|---------|-------------|
| `e-commerce-workflow/` | Order processing with payment, inventory, and shipping |
| `etl-pipeline/` | Data extraction, transformation, and loading workflow |
| `approval-system/` | Multi-level approval with conditional routing |

## Purpose

These examples demonstrate:
- Real-world workflow patterns
- Multi-language handler implementations
- Testing strategies
- Deployment configurations

## Status

📋 Planned
EOF

cat > examples/e-commerce-workflow/README.md << 'EOF'
# E-Commerce Workflow Example

Order processing workflow demonstrating:
- Diamond dependency patterns (parallel payment + inventory check)
- External API integration (payment gateway)
- Conditional routing (shipping method selection)
- Error handling and retries

## Status

📋 Planned
EOF

cat > examples/etl-pipeline/README.md << 'EOF'
# ETL Pipeline Example

Data processing workflow demonstrating:
- Batchable handlers for large datasets
- Checkpoint/resume for long-running processes
- Multiple data sources
- Transformation chains

## Status

📋 Planned
EOF

cat > examples/approval-system/README.md << 'EOF'
# Approval System Example

Multi-level approval workflow demonstrating:
- Decision handlers for routing
- Convergence patterns (all approvals required)
- Human-in-the-loop integration
- Timeout and escalation

## Status

📋 Planned
EOF

# =============================================================================
# Docs structure (keep existing but ensure directories exist)
# =============================================================================
echo "📁 Ensuring docs/ structure..."

mkdir -p docs/{ticket-specs/TAS-126,architecture,guides}
touch docs/architecture/.keep
touch docs/guides/.keep

# =============================================================================
# Copy Docker infrastructure from tasker-core
# =============================================================================
echo "📁 Copying Docker infrastructure from tasker-core..."

if [ -d "$TASKER_CORE/docker" ]; then
  # Copy the main docker-compose files
  cp "$TASKER_CORE/docker/docker-compose.dev.yml" ops/docker/development/docker-compose.yml 2>/dev/null || true
  cp "$TASKER_CORE/docker/docker-compose.test.yml" ops/docker/development/docker-compose.test.yml 2>/dev/null || true
  cp "$TASKER_CORE/docker/docker-compose.prod.yml" ops/docker/production/docker-compose.yml 2>/dev/null || true
  
  # Copy observability if it exists
  if [ -d "$TASKER_CORE/docker/observability" ]; then
    cp -r "$TASKER_CORE/docker/observability/"* ops/docker/observability/ 2>/dev/null || true
  fi
  
  # Copy README for reference
  cp "$TASKER_CORE/docker/README.md" ops/docker/TASKER-CORE-README.md 2>/dev/null || true
  cp "$TASKER_CORE/docker/QUICK-START.md" ops/docker/QUICK-START.md 2>/dev/null || true
  
  echo "   ✓ Docker files copied"
else
  echo "   ⚠ tasker-core/docker not found, skipping copy"
fi

# =============================================================================
# Verify .github workflows exist (created separately)
# =============================================================================
echo "📁 Verifying .github/ structure..."

if [ -d ".github/workflows" ]; then
  echo "   ✓ .github/workflows/ exists"
  ls -la .github/workflows/
else
  echo "   ⚠ .github/workflows/ not found - create manually"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "✅ Directory structure created!"
echo ""
echo "Created directories:"
find . -type d | grep -v ".git" | sort | head -40
echo "..."
echo ""
echo "Key files:"
echo "  - rails/tasker-cli-plugin/tasker-plugin.toml"
echo "  - python/tasker-cli-plugin/tasker-plugin.toml"
echo "  - typescript/tasker-cli-plugin/tasker-plugin.toml"
echo "  - rust/tasker-cli-plugin/tasker-plugin.toml"
echo "  - .github/workflows/ci.yml"
echo "  - .github/workflows/bleeding-edge.yml"
echo "  - .github/workflows/upstream-check.yml"
echo ""
echo "Next steps:"
echo "  1. Review structure"
echo "  2. Commit: git add -A && git commit -m 'feat: initial directory structure and CI'"
echo "  3. Update TAS-126 in Linear with LINEAR-TICKET.md content"
echo "  4. Create TAS-127 in tasker-core with TAS-127-CLI-PLUGIN-SYSTEM.md content"
