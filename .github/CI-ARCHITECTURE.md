# CI Architecture

## Overview

Tasker Contrib's CI validates that CLI plugin templates generate correct, syntactically valid code. No databases or services are required — `tasker-ctl` is a pure CLI tool for plugin discovery and template generation.

| Aspect | Description |
|--------|-------------|
| **What we test** | Plugin manifests + template generation + output syntax |
| **How we build** | Shallow-clone tasker-core, build tasker-ctl with sccache |
| **No services needed** | No PostgreSQL, no RabbitMQ, no Docker services |
| **Path-based triggers** | Only runs when relevant templates change |

## Workflows

### 1. CI (ci.yml)

**Purpose**: Validate plugin manifests and template output on every PR/merge.

**Triggers**: Push to main, Pull requests to main

**Jobs**:

| Job | Trigger Path | What It Does |
|-----|-------------|--------------|
| `build-tasker-ctl` | Any `*/tasker-cli-plugin/**` change | Builds tasker-ctl from tasker-core main |
| `validate-plugins` | (depends on build) | Runs `plugin validate` on all 5 plugins |
| `test-ruby-templates` | `rails/tasker-cli-plugin/**` | Generates Rails templates, `ruby -c` syntax check |
| `test-python-templates` | `python/tasker-cli-plugin/**` | Generates Python templates, `py_compile` check |
| `test-typescript-templates` | `typescript/tasker-cli-plugin/**` | Generates TS templates, `bun build` syntax check |
| `test-rust-templates` | `rust/tasker-cli-plugin/**` | Generates Rust templates, `rustfmt --check` |
| `test-ops-templates` | `ops/tasker-cli-plugin/**` | Generates ops templates, YAML/TOML validation |
| `docs` | `docs/**`, `*.md` | Markdown link checking |

### 2. Bleeding Edge (bleeding-edge.yml)

**Purpose**: Test templates against latest tasker-core main to catch compatibility issues early.

**Triggers**:
- Repository dispatch from tasker-core (`tasker-core-updated`)
- Manual dispatch (with optional `tasker_core_ref`)
- Nightly schedule (4 AM UTC)

**Jobs**:
1. **build-tasker-ctl**: Build from specified tasker-core ref
2. **validate-and-test**: Install all language toolchains, run full validation + generation across all plugins
3. **report**: Create/update GitHub issue on failure (label: `bleeding-edge-failure`)

### 3. Upstream Check (upstream-check.yml)

**Purpose**: Monitor for new tasker-core releases.

**Triggers**: Daily at 6 AM UTC, manual dispatch

**Registry checks**:
| Registry | Package |
|----------|---------|
| crates.io | `tasker-worker`, `tasker-orchestration`, `tasker-ctl`, `tasker-pgmq` |
| PyPI | `tasker_core` |
| RubyGems | `tasker-core-rb` |
| npm | `@tasker-systems/tasker` |

**Actions**: Creates GitHub issue when updates available (label: `upstream-update`)

## Composite Actions

| Action | Purpose |
|--------|---------|
| `.github/actions/build-tasker-core` | Clone tasker-core, install Rust/protobuf, build tasker-ctl with sccache |
| `.github/actions/setup-sccache` | Configure mozilla sccache with GHA backend |
| `.github/actions/setup-rust-cache` | Cache cargo registry + build artifacts |

## Build Strategy

We build `tasker-ctl` from source rather than distributing prebuilt binaries. This provides:

1. **Always up-to-date**: No binary distribution pipeline needed
2. **sccache makes it fast**: GHA-backed cache means rebuilds after minor changes are quick
3. **Cross-platform**: Build on the CI runner's own architecture
4. **Artifact sharing**: Build once, download in all per-language test jobs

## Version Tracking

`upstream-versions.json` tracks pinned versions for monitoring:

```json
{
  "rust": { "tasker-worker": "0.1.1", ... },
  "ruby": { "tasker-core-rb": "0.1.1" },
  "python": { "tasker_core": "0.1.1" },
  "typescript": { "@tasker-systems/tasker": "0.1.1" }
}
```

## Validation Tiers

| Tier | What | Status |
|------|------|--------|
| **Tier 1** | Generate templates + syntax check output | Implemented |
| **Tier 2** | Run generated tests against FFI packages | Future |
| **Tier 3** | Example apps with full services | Future |

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
```

## Cross-Repo Triggering

When tasker-core main merges successfully:

```yaml
# In tasker-core CI
- name: Trigger tasker-contrib bleeding edge
  if: github.ref == 'refs/heads/main'
  uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.CONTRIB_TRIGGER_TOKEN }}
    repository: tasker-systems/tasker-contrib
    event-type: tasker-core-updated
    client-payload: '{"ref": "${{ github.sha }}"}'
```

## Performance Targets

| Workflow | Cold Cache | Warm Cache |
|----------|------------|------------|
| CI (path-based) | 15 min | 8 min |
| Bleeding Edge | 18 min | 10 min |
| Upstream Check | 2 min | 2 min |

## Related Documentation

- [DEVELOPMENT.md](../../DEVELOPMENT.md) - Local development setup
- [tasker-core CLAUDE.md](https://github.com/tasker-systems/tasker-core/blob/main/CLAUDE.md) - Core project context
