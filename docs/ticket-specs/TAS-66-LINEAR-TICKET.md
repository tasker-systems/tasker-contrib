# TAS-66: Migrate Documentation to MkDocs Material

## Summary

Migrate from abandoned legacy GitBook (Node.js) to MkDocs Material for documentation. This provides active maintenance, better multi-language code tabs, and Python-native tooling.

---

## Why Migrate?

| Aspect | Legacy GitBook | MkDocs Material |
|--------|----------------|-----------------|
| Maintenance | Abandoned (~2018) | Active, 50k+ users |
| Code tabs | Plugin-based, fragile | Native, linked site-wide |
| Search | Slow, plugin-dependent | Fast, client-side |
| Build | npm dependency issues | Simple pip install |
| Theming | Limited | Modern, dark mode |

---

## Key Feature: Linked Content Tabs

MkDocs Material tabs are **linked across the entire site**. When a user clicks "Rails" on one page, ALL tabs switch to "Rails" everywhere.

This is perfect for our Core → Contrib progressive disclosure pattern:

```markdown
=== "Core (Pure)"
    ```ruby
    class PaymentHandler < TaskerCore::StepHandler::Base
    ```

=== "Rails"
    ```ruby
    # Generated via: rails g tasker:step_handler Payment
    class PaymentHandler < TaskerCore::StepHandler::Api
    ```
```

---

## New Documentation Structure

```
tasker-docs/
├── mkdocs.yml
├── docs/
│   ├── getting-started/
│   │   └── choosing-your-stack.md    # Core vs Contrib decision tree
│   ├── ecosystem/
│   │   ├── core/                     # tasker-core-* packages
│   │   └── contrib/                  # tasker-contrib-* packages
│   ├── stories/                      # Blog posts with linked tabs
│   ├── reference/                    # SYNCED from tasker-core/docs
│   └── api/                          # GENERATED from code
└── requirements.txt
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

## Implementation Phases

| Phase | Effort | Description |
|-------|--------|-------------|
| 1: Setup | 1-2 days | mkdocs.yml, requirements.txt, structure |
| 2: Migration | 2-3 days | Convert GitBook syntax to MkDocs |
| 3: Disambiguation | 1 day | Decision tree, ecosystem overview |
| 4: Tooling | 2 days | Sync scripts, API doc generation |
| 5: Story Rewrites | 5-7 days | Linked tabs (Core → Contrib) |
| 6: New Content | 3-4 days | Posts 06-08 |
| 7: Polish | 1-2 days | Theme, navigation |

**Total: 15-21 days**

---

## Migration Checklist

- [ ] Create new `tasker-docs` repo with MkDocs structure
- [ ] Write `mkdocs.yml` configuration
- [ ] Run migration script for GitBook → MkDocs syntax
- [ ] Manual cleanup of converted content
- [ ] Write `choosing-your-stack.md` disambiguation page
- [ ] Set up dual-source sync scripts
- [ ] Configure API doc generation (cargo doc, YARD, pdoc)
- [ ] Rewrite stories with linked Core/Contrib tabs
- [ ] Write posts 06-08
- [ ] Configure GitHub Pages deployment
- [ ] Redirect old GitBook URLs

---

## Dependencies

| Ticket | Blocks | Notes |
|--------|--------|-------|
| TAS-112 | Post 05 | Domain events |
| TAS-91 | Story tabs | Multi-language examples |
| TAS-126 | Contrib sync | Structure exists |
| TAS-127 | CLI docs | Template generation |

---

## Success Criteria

- [ ] "Which package?" answer findable in < 30 seconds
- [ ] Linked tabs work site-wide (click Rails, all tabs switch)
- [ ] Documentation auto-syncs from both repos
- [ ] API docs generated for Core and Contrib
- [ ] Build completes in < 60 seconds
- [ ] Dark mode works correctly

---

## Related Documentation

Full analysis: `docs/ticket-specs/TAS-66-MKDOCS-MIGRATION.md`
