# TAS-66 Linear Ticket Update

## Summary of Changes

With the establishment of `tasker-contrib`, the documentation strategy needs updating to address:

1. **Dual-source documentation** - syncing from both tasker-core AND tasker-contrib
2. **Disambiguation** - helping users choose between Core and Contrib packages
3. **Progressive disclosure** - blog examples showing Core foundation → Contrib enhancement

---

## Key Addition: Disambiguation Section

Users need a clear answer to: "Should I use `tasker-core-rb` or `tasker-contrib-rails`?"

**Answer:** Both, layered appropriately:
- **Tasker Core** = Foundation (handlers, types, FFI, domain events)
- **Tasker Contrib** = Developer Experience (generators, framework hooks, config DSLs)

New page: `getting-started/choosing-your-stack.md` with decision tree.

---

## Updated Blog Example Strategy

**Before:** Examples in one language per post
**After:** Progressive disclosure pattern

Each post shows:
1. **Core implementation** - Framework-agnostic, pure API
2. **Contrib enhancement** - Framework-specific ergonomics

This teaches fundamentals while demonstrating the DX improvement.

### Updated Story Mapping

| Story | Primary Lang | Core Example | Contrib Enhancement |
|-------|--------------|--------------|---------------------|
| 01: E-commerce | Ruby | tasker-core-rb | tasker-contrib-rails generators |
| 02: Data Pipeline | Python | tasker-core-py | tasker-contrib-fastapi hooks |
| 03: Microservices | TypeScript | tasker-core-ts | tasker-contrib-bun integration |
| 04: Team Scaling | All 4 | Core only (polyglot focus) | N/A |
| 05: Observability | Rust + Ruby | OTel + Domain Events | AS::Notifications bridge |
| 06: Batch Processing | Rust | Core Rust worker | N/A |
| 07: Conditional | Python | Core decision handlers | FastAPI fixtures |
| 08: Debugging | Ruby | Core DLQ investigation | Rails console integration |

---

## Updated GitBook Structure

```
tasker-gitbook/
├── getting-started/
│   └── choosing-your-stack.md    # NEW: Core vs Contrib decision tree
│
├── ecosystem/                     # NEW SECTION
│   ├── core/                      # tasker-core-* packages
│   ├── contrib/                   # tasker-contrib-* packages
│   └── disambiguation.md
│
├── stories/
│   └── {post}/
│       ├── core-implementation.md    # Pure tasker-core-* examples
│       └── {framework}-integration.md # tasker-contrib-* enhancement
│
├── reference/                     # SYNCED from tasker-core/docs
│
└── api/
    ├── core/                      # Generated from tasker-core
    └── contrib/                   # Generated from tasker-contrib
```

---

## Dual-Source Sync

**From tasker-core:**
- `docs/` → `reference/`
- Generated API docs → `api/core/`

**From tasker-contrib:**
- `docs/` → `ecosystem/contrib/`
- Generated API docs → `api/contrib/`

---

## Updated Phases

| Phase | Effort | Description |
|-------|--------|-------------|
| **1: Foundation** | 2-3 days | Fresh gitbook with new structure |
| **2: Disambiguation** | 1 day | Decision tree, ecosystem overview |
| **3: Tooling** | 2 days | Dual-source sync from core + contrib |
| **4: Story Rewrites** | 5-7 days | Progressive disclosure (Core → Contrib) |
| **5: New Content** | 3-4 days | Posts 06-08 |
| **6: Polish** | 1-2 days | Link validation, navigation |

**Total estimate:** 14-19 days (increased from 11-17 due to contrib integration)

---

## New Dependencies

- **TAS-126** (tasker-contrib): Contrib structure must exist for docs sync
- **TAS-127** (tasker-core): CLI plugin system for generator documentation

---

## TAS-91 Impact

TAS-91 (multi-language blog examples) stays focused on **Core** examples:
- 27 handlers × 4 languages in `tasker-core/workers/*/`

New consideration: **Contrib example apps** (full integration demos)
- Could be separate ticket or Phase 5 of TAS-66
- Location: `tasker-contrib/examples/`
- Shows complete Rails/FastAPI/Bun apps with Tasker integration

---

## Related Documentation

Full analysis: `tasker-contrib/docs/ticket-specs/TAS-66-GITBOOK-UPDATE.md`
