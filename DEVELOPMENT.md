# Development Guide

This guide covers local development setup for tasker-contrib, with particular attention to managing dependencies on [tasker-core](https://github.com/tasker-systems/tasker-core).

---

## Prerequisites

- **tasker-core** cloned locally (for development)
- PostgreSQL 15+ with PGMQ extension
- Language toolchains for packages you're working on:
  - Ruby 3.2+ and Bundler
  - Python 3.11+ and uv/pip
  - Node.js 20+ or Bun 1.0+
  - Rust 1.75+ (for tasker-cli and FFI extensions)

## Repository Layout

We recommend this directory structure for development:

```
tasker-systems/
├── tasker-core/              # Core orchestration engine
├── tasker-contrib/           # This repository
└── tasker-engine/            # Legacy reference (optional)
```

---

## Cross-Repository Dependencies

Tasker Contrib packages depend on Tasker Core packages. During development, you'll want to use local builds. For releases, packages reference published versions.

### Strategy Overview

| Context | Ruby | Python | TypeScript | Rust |
|---------|------|--------|------------|------|
| **Local Dev** | `path:` in Gemfile | `-e` editable install | `file:` or `link:` | `path` in Cargo.toml |
| **CI/Release** | Version in gemspec | Version in pyproject.toml | Version in package.json | Version in Cargo.toml |

### Ruby (tasker-contrib-rails)

**Local Development:**

```ruby
# rails/tasker-contrib-rails/Gemfile

source 'https://rubygems.org'

gemspec

# Development: use local tasker-core-rb
# Assumes tasker-core is checked out at ../../tasker-core relative to this repo
gem 'tasker-core-rb', path: '../../../../tasker-core/workers/ruby'
```

**Release (gemspec):**

```ruby
# rails/tasker-contrib-rails/tasker-contrib-rails.gemspec

Gem::Specification.new do |spec|
  spec.name = 'tasker-contrib-rails'
  spec.version = TaskerContribRails::VERSION

  # Release: reference published gem
  spec.add_dependency 'tasker-core-rb', '~> 0.5.0'
  
  # Rails version requirements
  spec.add_dependency 'railties', '>= 7.0', '< 8.0'
end
```

**Switching Modes:**

```bash
# For local development (uses Gemfile path:)
cd rails/tasker-contrib-rails
bundle config set --local path 'vendor/bundle'
bundle install

# For release testing (uses gemspec version)
cd rails/tasker-contrib-rails
BUNDLE_GEMFILE=Gemfile.release bundle install
```

**Gemfile.release pattern:**

```ruby
# rails/tasker-contrib-rails/Gemfile.release
source 'https://rubygems.org'

gemspec

# No path overrides - uses gemspec dependencies
```

### Python (tasker-contrib-fastapi)

**Local Development:**

```toml
# python/tasker-contrib-fastapi/pyproject.toml

[project]
name = "tasker-contrib-fastapi"
version = "0.1.0"
dependencies = [
    "tasker-core-py>=0.5.0",
    "fastapi>=0.100.0",
]

[tool.uv]
# Development overrides for local tasker-core
dev-dependencies = [
    "pytest>=8.0",
    "pytest-asyncio>=0.23",
]

[tool.uv.sources]
# Local development: point to local tasker-core-py
tasker-core-py = { path = "../../../../tasker-core/workers/python", editable = true }
```

**Alternative: pip editable install:**

```bash
# Install local tasker-core-py in editable mode
cd ../tasker-core/workers/python
pip install -e .

# Then install tasker-contrib-fastapi
cd ../tasker-contrib/python/tasker-contrib-fastapi
pip install -e .
```

### TypeScript (tasker-contrib-express)

**Local Development:**

```json
// typescript/tasker-contrib-express/package.json
{
  "name": "tasker-contrib-express",
  "version": "0.1.0",
  "dependencies": {
    "express": "^4.18.0"
  },
  "peerDependencies": {
    "tasker-core-ts": ">=0.5.0"
  },
  "devDependencies": {
    "tasker-core-ts": "file:../../../../tasker-core/workers/typescript"
  }
}
```

**Using npm/yarn link:**

```bash
# Link tasker-core-ts globally
cd ../tasker-core/workers/typescript
npm link

# Use linked package in contrib
cd ../tasker-contrib/typescript/tasker-contrib-express
npm link tasker-core-ts
```

**Using Bun workspaces (alternative):**

```json
// tasker-contrib/package.json (workspace root)
{
  "workspaces": [
    "typescript/*"
  ]
}
```

### Rust (tasker-contrib-axum)

**Local Development:**

```toml
# rust/tasker-contrib-axum/Cargo.toml

[package]
name = "tasker-contrib-axum"
version = "0.1.0"

[dependencies]
axum = "0.7"

# Local development: path dependency
tasker-worker = { path = "../../../../tasker-core/tasker-worker" }
tasker-shared = { path = "../../../../tasker-core/tasker-shared" }
```

**Release:**

```toml
# rust/tasker-contrib-axum/Cargo.toml

[dependencies]
axum = "0.7"

# Release: crates.io version
tasker-worker = "0.5"
tasker-shared = "0.5"
```

**Using Cargo patch (workspace-level):**

```toml
# tasker-contrib/Cargo.toml (workspace root)

[workspace]
members = ["rust/*"]

# Override for all workspace members during development
[patch.crates-io]
tasker-worker = { path = "../tasker-core/tasker-worker" }
tasker-shared = { path = "../tasker-core/tasker-shared" }
```

---

## Development Workflow

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

# Set up tasker-contrib
cd ../../tasker-contrib
# Follow package-specific setup below
```

### Working on tasker-contrib-rails

```bash
cd rails/tasker-contrib-rails

# Install dependencies (uses local tasker-core-rb via Gemfile path:)
bundle install

# Run tests
bundle exec rspec

# Test generators in dummy app
cd spec/dummy
bundle exec rails generate tasker:install
bundle exec rails generate tasker:step_handler TestHandler
```

### Working on tasker-contrib-fastapi

```bash
cd python/tasker-contrib-fastapi

# Install with local tasker-core-py
uv sync  # or pip install -e .

# Run tests
pytest

# Test in example app
cd examples/basic
uvicorn main:app --reload
```

### Working on tasker-contrib-express

```bash
cd typescript/tasker-contrib-express

# Install dependencies
bun install

# Run tests
bun test

# Build
bun run build
```

---

## Testing Against Published Packages

Before release, verify packages work with published dependencies:

### Ruby

```bash
cd rails/tasker-contrib-rails

# Create a clean environment
rm -rf vendor/bundle .bundle

# Install from gemspec (no local overrides)
BUNDLE_GEMFILE=Gemfile.release bundle install

# Run tests
BUNDLE_GEMFILE=Gemfile.release bundle exec rspec
```

### Python

```bash
cd python/tasker-contrib-fastapi

# Create clean venv
python -m venv .venv-release
source .venv-release/bin/activate

# Install without local overrides
pip install . --no-deps
pip install tasker-core-py  # From PyPI

# Run tests
pytest
```

---

## Environment Variables

### Required for Integration Tests

```bash
# PostgreSQL connection (with PGMQ extension)
export DATABASE_URL="postgresql://tasker:tasker@localhost:5432/tasker_contrib_test"

# Tasker environment
export TASKER_ENV="test"
```

### Optional Development Settings

```bash
# Point to local tasker-core for CLI tools
export TASKER_CLI_PATH="../tasker-core/target/release/tasker-cli"

# Enable verbose logging
export RUST_LOG="debug"
export TASKER_LOG_LEVEL="debug"
```

---

## CI Configuration

CI should test both local and published dependency scenarios:

```yaml
# .github/workflows/test.yml
jobs:
  test-with-local:
    name: Test with local tasker-core
    steps:
      - uses: actions/checkout@v4
        with:
          path: tasker-contrib
      
      - uses: actions/checkout@v4
        with:
          repository: tasker-systems/tasker-core
          path: tasker-core
      
      - name: Build tasker-core
        working-directory: tasker-core
        run: |
          cargo build --release
          cd workers/ruby && bundle install && rake compile
      
      - name: Test tasker-contrib-rails
        working-directory: tasker-contrib/rails/tasker-contrib-rails
        run: |
          bundle install
          bundle exec rspec

  test-with-published:
    name: Test with published tasker-core
    steps:
      - uses: actions/checkout@v4
      
      - name: Test tasker-contrib-rails
        working-directory: rails/tasker-contrib-rails
        run: |
          BUNDLE_GEMFILE=Gemfile.release bundle install
          BUNDLE_GEMFILE=Gemfile.release bundle exec rspec
```

---

## Release Process

### Pre-Release Checklist

1. **Update version numbers** in all affected packages
2. **Update CHANGELOG.md** for each package
3. **Test with published tasker-core** (not local)
4. **Update dependency version constraints** if tasker-core had breaking changes

### Publishing

```bash
# Ruby
cd rails/tasker-contrib-rails
gem build tasker-contrib-rails.gemspec
gem push tasker-contrib-rails-0.1.0.gem

# Python
cd python/tasker-contrib-fastapi
uv build
uv publish

# TypeScript
cd typescript/tasker-contrib-express
npm publish

# Rust
cd rust/tasker-contrib-axum
cargo publish
```

---

## Troubleshooting

### "tasker-core-rb not found"

Ensure tasker-core is built and the path in Gemfile is correct:

```bash
# Check the FFI extension exists
ls ../tasker-core/workers/ruby/lib/tasker_core/tasker_worker_rb.bundle

# Rebuild if necessary
cd ../tasker-core/workers/ruby
bundle exec rake compile
```

### "FFI library load error"

The Rust FFI extension must be compiled for your platform:

```bash
cd ../tasker-core
cargo build --release

# For Ruby
cd workers/ruby
bundle exec rake compile
```

### "Database connection failed"

Ensure PostgreSQL is running with PGMQ:

```bash
# Using Docker
docker run -d \
  --name tasker-postgres \
  -e POSTGRES_USER=tasker \
  -e POSTGRES_PASSWORD=tasker \
  -e POSTGRES_DB=tasker_contrib_test \
  -p 5432:5432 \
  quay.io/tembo/pg17-pgmq:latest

# Run migrations from tasker-core
cd ../tasker-core
DATABASE_URL="postgresql://tasker:tasker@localhost/tasker_contrib_test" \
  cargo run --bin tasker-cli -- migrate
```

---

## Contributing

### Adding a New Framework Integration

1. Create directory structure: `{language}/tasker-contrib-{framework}/`
2. Set up package manifest with tasker-core dependency
3. Implement Railtie/lifespan/middleware pattern
4. Add generators that wrap `tasker-cli`
5. Write tests including integration tests
6. Document in README

### Code Style

- **Ruby**: Follow RuboCop with Rails conventions
- **Python**: Follow Ruff/Black formatting
- **TypeScript**: Follow Biome/ESLint configuration
- **Rust**: Follow rustfmt and Clippy

### Pull Request Process

1. Create feature branch from `main`
2. Ensure tests pass with both local and published dependencies
3. Update documentation as needed
4. Request review from maintainers
