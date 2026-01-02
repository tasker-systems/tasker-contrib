# TAS-126: Tasker Contrib Foundations

## Summary

Establish the `tasker-contrib` repository structure, vision documentation, CI infrastructure, and foundational architecture. This is the groundwork that enables all subsequent framework-specific milestones (Rails, Python, TypeScript).

## Background

Tasker Core provides powerful, framework-agnostic workflow orchestration. However, the barrier to entry is high because developers must figure out framework integration patterns themselves. Tasker Contrib bridges this gap with framework-specific integrations, starter templates, and operational tooling.

**Repository**: https://github.com/tasker-systems/tasker-contrib

## Scope

### Deliverables

1. **Repository Structure**
   - Directory layout: `rails/`, `python/`, `typescript/`, `rust/`, `ops/`, `examples/`
   - CLI plugin structure with `tasker-plugin.toml` manifests per language
   - Placeholder READMEs documenting purpose of each directory

2. **Vision Documentation**
   - `README.md` with architectural principles and responsibility boundaries
   - `DEVELOPMENT.md` with cross-repo dependency patterns
   - Ticket specs in `docs/ticket-specs/TAS-126/`

3. **CLI Plugin Architecture Design**
   - Plugin manifest format specification
   - Template structure design
   - Configuration file design (`.config/tasker-cli.toml`, like nextest)
   - **Note**: Implementation is TAS-127 in tasker-core

4. **CI Infrastructure**
   - Path-based CI (only run relevant framework tests)
   - Bleeding-edge builds against tasker-core main
   - Pinned semver builds for release stability
   - Upstream version checking (faster than dependabot)

5. **Docker Infrastructure**
   - Copy and adapt docker/ from tasker-core into `ops/docker/`

### Out of Scope (Separate Milestones/Tickets)

- TAS-127: CLI plugin loading implementation (tasker-core)
- Rails milestone: tasker-contrib-rails gem
- Python milestone: tasker-contrib-fastapi package  
- TypeScript milestone: tasker-contrib-bun package

## Architecture

### Repository Structure

```
tasker-contrib/
├── rails/
│   ├── tasker-contrib-rails/     # Ruby gem
│   ├── tasker-cli-plugin/        # CLI plugin with templates
│   └── tasker-rails-template/    # App template
├── python/
│   ├── tasker-contrib-fastapi/   # Python package
│   ├── tasker-cli-plugin/        # CLI plugin with templates
│   └── tasker-fastapi-template/
├── typescript/
│   ├── tasker-contrib-bun/       # Bun-focused (not Express)
│   ├── tasker-cli-plugin/
│   └── tasker-bun-template/
├── rust/
│   ├── tasker-contrib-axum/
│   ├── tasker-cli-plugin/
│   └── tasker-axum-template/
├── ops/
│   ├── helm/
│   ├── terraform/
│   ├── docker/
│   └── monitoring/
├── examples/
├── .github/
│   └── workflows/
└── docs/
```

### CLI Plugin Design

Each language has a `tasker-cli-plugin/` directory with:

```toml
# tasker-plugin.toml
[plugin]
name = "tasker-contrib-rails"
version = "0.1.0"
languages = ["ruby"]
frameworks = ["rails"]

[templates]
step-handler = { path = "templates/step_handler" }
step-handler-api = { path = "templates/step_handler_api" }
```

Templates are loaded at runtime by `tasker-cli` (TAS-127), not compiled in.

### CI Strategy

**Path-Based Triggering**: Unlike tasker-core which runs holistic CI for coherence, tasker-contrib only runs relevant tests:

| Path Changed | CI Jobs Run |
|--------------|-------------|
| `rails/**` | Ruby tests only |
| `python/**` | Python tests only |
| `typescript/**` | TypeScript tests only |
| `ops/**` | Infrastructure validation |
| `docs/**` | Doc linting only |

**Dual Build Modes**:
1. **Bleeding-edge**: Triggered by tasker-core main merge, tests against latest
2. **Pinned**: Uses declared semver dependencies, runs on PR/merge

### Key Decisions

1. **Bun over Express** - TypeScript integration focuses on Bun for simplicity
2. **CLI plugin architecture** - Templates loaded at runtime, not compiled into binary
3. **Path-based CI** - Only run relevant tests when specific paths change
4. **Bleeding-edge + pinned builds** - CI supports both development and stability

## Blocked By

- **TAS-127** (tasker-core): CLI plugin system must exist before generators can delegate to `tasker-cli template generate`

## Acceptance Criteria

- [ ] Directory structure created with READMEs
- [ ] CLI plugin manifests (`tasker-plugin.toml`) for all languages
- [ ] Vision documentation complete (README.md, DEVELOPMENT.md)
- [ ] CI workflows configured (.github/workflows/)
- [ ] Docker infrastructure copied from tasker-core
- [ ] TAS-127 linked as blocker

## Documentation

- `docs/ticket-specs/TAS-126/foundations.md` - Architectural deep-dive
- `docs/ticket-specs/TAS-126/rails.md` - Rails implementation plan
- `docs/ticket-specs/TAS-126/cli-plugin-architecture.md` - CLI plugin design
