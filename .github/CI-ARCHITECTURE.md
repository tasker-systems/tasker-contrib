# CI Architecture

## Overview

Tasker Contrib's CI has two concerns: validating CLI plugin templates and testing the example applications against published Tasker infrastructure.

| Aspect | Description |
|--------|-------------|
| **Template validation** | Plugin manifests + template generation + output syntax checks |
| **Example app testing** | Integration tests against docker-compose with published GHCR images |
| **How we get tasker-ctl** | `cargo install tasker-ctl` from crates.io |
| **Path-based triggers** | Workflows only run when relevant files change |

## Workflows

### 1. CI (ci.yml)

**Purpose**: Validate plugin manifests and template output on every PR/merge.

**Triggers**: Push to main, Pull requests to main

**Jobs**:

| Job | Trigger Path | What It Does |
|-----|-------------|--------------|
| `build-tasker-ctl` | Any `*/tasker-cli-plugin/**` change | Installs tasker-ctl from crates.io |
| `validate-plugins` | (depends on build) | Runs `plugin validate` on all 5 plugins |
| `test-ruby-templates` | `rails/tasker-cli-plugin/**` | Generates Rails templates, `ruby -c` syntax check |
| `test-python-templates` | `python/tasker-cli-plugin/**` | Generates Python templates, `py_compile` check |
| `test-typescript-templates` | `typescript/tasker-cli-plugin/**` | Generates TS templates, `bun build` syntax check |
| `test-rust-templates` | `rust/tasker-cli-plugin/**` | Generates Rust templates, `rustfmt --check` |
| `test-ops-templates` | `ops/tasker-cli-plugin/**` | Generates ops templates, YAML/TOML validation |
| `docs` | `docs/**`, `*.md` | Markdown link checking |
| `test-examples` | `examples/**` | Calls `test-examples.yml` (below) |
| `ci-success` | always | **CI Success** — the one required check (below) |

A change to `ci.yml` itself puts every job in scope, so a broken change-detection rule cannot
quietly skip the checks it was meant to select.

#### CI Success

`CI Success` is the only check branch protection needs to require. It lists every job in `ci.yml`
with the scope condition that makes it run, and passes only when each in-scope job **succeeded** and
each out-of-scope job was **skipped**. A failure, a cancellation, or an in-scope job that was
skipped (because a job it depends on was skipped or failed) fails it, and so does a failure of
change detection itself. Its step summary shows the table of scope and result per job.

When you add a job to `ci.yml`, add it to `ci-success`'s `needs` and to its `check` list with the
same scope condition, or it will not be gated.

### 2. Test Examples (test-examples.yml)

**Purpose**: Run integration tests for all four example apps against real Tasker infrastructure.

**Triggers**: called from `ci.yml` (job `test-examples`) when `examples/**`, this workflow or
`ci.yml` changes, so its result reports under `CI Success`. It has no push or pull-request trigger
of its own — a path-filtered workflow never reports on a PR outside its paths, so it could not be a
required check. It can also be run by hand (`workflow_dispatch`).

**Infrastructure**: `docker compose up -d` from `examples/` starts:
- `tasker-postgres` (PostgreSQL 18 + PGMQ + app databases)
- `tasker-orchestration` (published GHCR image)
- `dragonfly` (Redis-compatible cache)
- `rabbitmq` (messaging backend)

**Per-app testing** (sequential, shared infrastructure):

| App | Setup | Migrate | Test Command |
|-----|-------|---------|--------------|
| FastAPI | `uv sync` | `uv run alembic upgrade head` | `uv run pytest tests/ -v` |
| Bun | `bun install` | `bun run db:migrate` | `bun test tests/` |
| Rails | `bundle install` (cached) | `bundle exec rake db:migrate` | `bundle exec rspec spec/integration/ --format documentation` |
| Axum | sccache + nextest | automatic (sqlx) | `cargo nextest run` |

All test failures are hard failures — no `continue-on-error`.

### 3. Upstream Check (upstream-check.yml)

**Purpose**: Monitor for new tasker-core releases across all package registries.

**Triggers**: Daily at 6 AM UTC, manual dispatch

**Registry checks**:

| Registry | Package |
|----------|---------|
| crates.io | `tasker-worker`, `tasker-orchestration`, `tasker-ctl`, `tasker-pgmq` |
| PyPI | `tasker_core` |
| RubyGems | `tasker-core-rb` |
| npm | `@tasker-systems/tasker` |

**Actions**: Creates GitHub issue when updates available (label: `upstream-update`)

## Build Strategy

We install `tasker-ctl` from crates.io rather than building from source:

1. **No cross-repo clone**: No need to fetch tasker-core source
2. **No protobuf compiler**: Binary is pre-compiled
3. **Cargo caching**: Registry + git caches make installs fast after first run
4. **Artifact sharing**: Install once, download in all per-language test jobs

## Validation Tiers

| Tier | What | Status |
|------|------|--------|
| **Tier 1** | Generate templates + syntax check output | Implemented (ci.yml) |
| **Tier 2** | Run generated tests against FFI packages | Future |
| **Tier 3** | Example apps with full services | Implemented (test-examples.yml) |

## Version Tracking

`upstream-versions.json` tracks pinned versions for monitoring:

```json
{
  "rust": { "tasker-worker": "0.1.4", ... },
  "ruby": { "tasker-core-rb": "0.1.4" },
  "python": { "tasker_core": "0.1.4" },
  "typescript": { "@tasker-systems/tasker": "0.1.4" }
}
```

## Local Development

```bash
# Install cargo-make if needed
cargo install cargo-make

# Build tasker-ctl from sibling tasker-core repo
cargo make build-ctl

# Validate all plugin manifests
cargo make validate

# Run full template generation + syntax checks
cargo make test-templates

# Or run both
cargo make test-all

# Run example app tests (requires docker-compose infrastructure)
cargo make test-examples
```

## Performance Targets

| Workflow | Cold Cache | Warm Cache |
|----------|------------|------------|
| CI (path-based) | 10 min | 5 min |
| Test Examples | 15 min | 10 min |
| Upstream Check | 2 min | 2 min |

## Related Documentation

- [DEVELOPMENT.md](../../DEVELOPMENT.md) - Local development setup
- [tasker-core CLAUDE.md](https://github.com/tasker-systems/tasker-core/blob/main/CLAUDE.md) - Core project context
