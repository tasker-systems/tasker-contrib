# TAS-126: Tasker Contrib Foundations

**Status**: In Progress
**Priority**: High
**Project**: [Tasker Contrib](https://linear.app/tasker-systems/project/tasker-contrib-1f8c15f1e3e2)
**Milestone**: Foundations and CLI

---

## Summary

TAS-126 establishes the `tasker-contrib` repository structure, vision documentation, and foundational architecture. This is the groundwork ticket that enables all subsequent framework-specific milestones.

## Scope

### In Scope (This Ticket)

1. **Repository Structure**
   - Directory layout for rails/, python/, typescript/, rust/, ops/, examples/
   - CLI plugin structure with `tasker-plugin.toml` manifests
   - Placeholder READMEs documenting purpose of each directory

2. **Vision Documentation**
   - README.md with architectural principles
   - DEVELOPMENT.md with cross-repo dependency patterns
   - Responsibility boundaries (Core vs Contrib)

3. **CLI Plugin Architecture Design**
   - Plugin manifest format (`tasker-plugin.toml`)
   - Template structure design
   - Configuration file design (`.config/tasker-cli.toml`)

4. **Initial Rails CLI Plugin**
   - `rails/tasker-cli-plugin/tasker-plugin.toml` manifest
   - Template directory structure (placeholders)

### Out of Scope (Separate Tickets)

- **TAS-127** (tasker-core): CLI plugin loading implementation (Tera templates)
- **Rails Milestone**: tasker-contrib-rails gem implementation
- **Python Milestone**: tasker-contrib-fastapi package implementation
- **TypeScript Milestone**: tasker-contrib-bun package implementation
- **Ops**: Helm charts, Terraform modules

## Documents

| Document | Description |
|----------|-------------|
| [foundations.md](./foundations.md) | Architectural deep-dive: design rationale, patterns |
| [rails.md](./rails.md) | Rails-specific implementation plan (for Rails milestone) |
| [cli-plugin-architecture.md](./cli-plugin-architecture.md) | CLI plugin system design (implemented in TAS-127) |

## Deliverables

- [x] Repository created on GitHub
- [x] Vision documentation (README.md)
- [x] Development guide (DEVELOPMENT.md)
- [x] Architectural documentation (docs/ticket-specs/TAS-126/)
- [ ] Directory structure created (rails/, python/, typescript/, rust/, ops/, examples/)
- [ ] CLI plugin manifests for each language
- [ ] Docker infrastructure copied from tasker-core

## Key Decisions

1. **Separate repository** - Contrib depends on Core, allows independent releases
2. **CLI plugin architecture** - `tasker-cli` loads templates at runtime (TAS-127)
3. **Bun over Express** - TypeScript integration focuses on Bun for simplicity
4. **Profile-based config** - `.config/tasker-cli.toml` for plugin paths (like nextest)
5. **Thin integrations** - Translate idioms, don't duplicate logic

## Related Tickets

| Ticket | Repository | Description |
|--------|------------|-------------|
| TAS-127 | tasker-core | CLI plugin system implementation (Tera templates) |
| TBD | tasker-contrib | Rails milestone: tasker-contrib-rails gem |
| TBD | tasker-contrib | Python milestone: tasker-contrib-fastapi |
| TBD | tasker-contrib | TypeScript milestone: tasker-contrib-bun |

## Notes

The CLI plugin architecture design lives in this ticket's documentation, but the actual implementation is TAS-127 in tasker-core. This separation reflects the responsibility boundary: tasker-core owns the CLI binary and plugin loading mechanism, tasker-contrib owns the plugin content (templates).
