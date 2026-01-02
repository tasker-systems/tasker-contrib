# TAS-66 Updated Documentation Plan

## Context: The Core vs Contrib Split

With tasker-contrib now established, we have a clear separation:

| Layer | Purpose | Examples |
|-------|---------|----------|
| **Tasker Core** | Foundation - framework-agnostic | tasker-core-rb, tasker-core-py, tasker-core-ts |
| **Tasker Contrib** | Developer Experience - framework-specific | tasker-contrib-rails, tasker-contrib-fastapi, tasker-contrib-bun |

This split creates a documentation challenge: **which library should blog examples use?**

---

## The Disambiguation Problem

Users landing on our documentation will ask:

> "I'm building a Rails app. Should I use `tasker-core-rb` or `tasker-contrib-rails`?"

**Answer:** Both, but understand what each provides:

| Use Case | Recommendation |
|----------|----------------|
| Learning Tasker concepts | tasker-core-* (pure API, no framework sugar) |
| Production Rails app | tasker-contrib-rails + tasker-core-rb |
| Polyglot/multi-framework | tasker-core-* (portable across frameworks) |
| CI/testing | tasker-core-* (minimal dependencies) |
| Generators, initializers | tasker-contrib-* (framework integration) |

**The rule:** Tasker Contrib is a thin wrapper that makes Tasker Core more ergonomic within a specific framework. You always use Core under the hood.

---

## Blog Examples: Progressive Disclosure Approach

Rather than choosing Core OR Contrib, we use **progressive disclosure**:

### Pattern: Foundation → Enhancement

Each blog post shows:
1. **The Core approach** - Framework-agnostic, works everywhere
2. **The Contrib enhancement** - Framework-specific ergonomics (where applicable)

This teaches fundamentals while demonstrating the developer experience improvement.

### Updated Story Mapping

| Story | Primary Language | Core Example | Contrib Enhancement |
|-------|------------------|--------------|---------------------|
| 01: E-commerce Checkout | Ruby | tasker-core-rb handlers | tasker-contrib-rails generators |
| 02: Data Pipeline | Python | tasker-core-py handlers | tasker-contrib-fastapi lifespan hooks |
| 03: Microservices | TypeScript | tasker-core-ts handlers | tasker-contrib-bun Bun.serve integration |
| 04: Team Scaling | All 4 (tabs) | Core only (polyglot focus) | N/A - demonstrates framework independence |
| 05: Observability | Rust + Ruby | OTel (Rust), Domain Events (Ruby Core) | AS::Notifications bridge (Rails Contrib) |
| 06: Batch Processing | Rust | tasker-core Rust worker | N/A - Rust doesn't need framework sugar |
| 07: Conditional Workflows | Python | tasker-core-py decision handlers | tasker-contrib-fastapi testing fixtures |
| 08: Production Debugging | Ruby | Core DLQ investigation | Contrib Rails console integration |

### Example: Post 01 Structure

```markdown
# E-commerce Checkout Reliability

## The Foundation (tasker-core-rb)

Here's the pure handler implementation:

```ruby
# Using tasker-core-rb directly
class PaymentHandler < TaskerCore::StepHandler::Base
  def call(context)
    # ...
  end
end
```

## The Rails Enhancement (tasker-contrib-rails)

With tasker-contrib-rails, you get generators and Rails integration:

```bash
rails generate tasker:step_handler Payment --type api
```

This creates the handler AND:
- Registers with Spring for auto-reload
- Adds to handler registry initializer
- Creates RSpec scaffolding
```

---

## Updated GitBook Structure

```
tasker-gitbook/
├── book.json
├── SUMMARY.md
├── README.md                          # "What is Tasker?"
│
├── getting-started/
│   ├── README.md
│   ├── quick-start.md                 # Points to tasker-core
│   ├── concepts.md                    # Core vocabulary
│   └── choosing-your-stack.md         # NEW: Core vs Contrib decision tree
│
├── ecosystem/                         # NEW SECTION
│   ├── README.md                      # Overview of all packages
│   ├── core/                          # Tasker Core packages
│   │   ├── README.md
│   │   ├── ruby.md                    # tasker-core-rb
│   │   ├── python.md                  # tasker-core-py
│   │   ├── typescript.md              # tasker-core-ts
│   │   └── rust.md                    # tasker-worker (Rust)
│   ├── contrib/                       # Tasker Contrib packages
│   │   ├── README.md
│   │   ├── rails.md                   # tasker-contrib-rails
│   │   ├── fastapi.md                 # tasker-contrib-fastapi
│   │   ├── bun.md                     # tasker-contrib-bun
│   │   └── axum.md                    # tasker-contrib-axum
│   └── disambiguation.md              # When to use what
│
├── stories/                           # Narrative blog series
│   ├── README.md
│   ├── 01-ecommerce-reliability/
│   │   ├── README.md
│   │   ├── the-story.md
│   │   ├── core-implementation.md     # tasker-core-rb examples
│   │   └── rails-integration.md       # tasker-contrib-rails enhancement
│   ├── 02-data-pipeline-resilience/
│   │   ├── ...
│   │   ├── core-implementation.md     # tasker-core-py examples
│   │   └── fastapi-integration.md     # tasker-contrib-fastapi enhancement
│   └── ...
│
├── reference/                         # SYNCED from tasker-core/docs
│   ├── README.md
│   ├── architecture/
│   ├── guides/
│   ├── workers/
│   ├── principles/
│   ├── decisions/
│   └── observability/
│
├── api/                               # GENERATED from code
│   ├── core/
│   │   ├── rust/                      # cargo doc
│   │   ├── ruby/                      # YARD
│   │   ├── python/                    # pdoc (placeholder)
│   │   └── typescript/                # TypeDoc (placeholder)
│   └── contrib/
│       ├── rails/                     # YARD
│       ├── fastapi/                   # pdoc
│       ├── bun/                       # TypeDoc
│       └── axum/                      # cargo doc
│
└── archive/                           # Legacy (temporary)
```

---

## Dual-Source Documentation Generation

### From tasker-core

```toml
# tasker-core/cargo-make/docs.toml

[tasks.docs-sync-core]
description = "Sync tasker-core/docs to gitbook"
script = ["${SCRIPTS_DIR}/docs/sync-core-markdown.sh"]

[tasks.docs-generate-core-api]
dependencies = [
    "docs-generate-rust-api",
    "docs-generate-ruby-api",
    "docs-generate-python-api",
    "docs-generate-typescript-api",
]
```

**Syncs:**
- `tasker-core/docs/` → `tasker-gitbook/reference/`
- `tasker-core/target/doc/` → `tasker-gitbook/api/core/rust/`
- `tasker-core/workers/ruby/doc/` → `tasker-gitbook/api/core/ruby/`

### From tasker-contrib

```toml
# tasker-contrib/cargo-make/docs.toml (future)

[tasks.docs-sync-contrib]
description = "Sync tasker-contrib/docs to gitbook"
script = ["${SCRIPTS_DIR}/docs/sync-contrib-markdown.sh"]

[tasks.docs-generate-contrib-api]
dependencies = [
    "docs-generate-rails-api",
    "docs-generate-fastapi-api",
    "docs-generate-bun-api",
    "docs-generate-axum-api",
]
```

**Syncs:**
- `tasker-contrib/docs/` → `tasker-gitbook/ecosystem/contrib/`
- `tasker-contrib/rails/tasker-contrib-rails/doc/` → `tasker-gitbook/api/contrib/rails/`

### Unified Build

```toml
# tasker-gitbook/Makefile.toml or gitbook itself

[tasks.docs-full-sync]
description = "Sync from both tasker-core and tasker-contrib"
dependencies = [
    "docs-sync-core",
    "docs-sync-contrib",
]
```

---

## The Disambiguation Page

`getting-started/choosing-your-stack.md` or `ecosystem/disambiguation.md`:

```markdown
# Choosing Your Stack

## Quick Decision Tree

```
Are you using a web framework (Rails, FastAPI, Bun)?
├── Yes → Use tasker-contrib-{framework} + tasker-core-{lang}
└── No → Use tasker-core-{lang} directly

Do you need generators and framework integration?
├── Yes → tasker-contrib-*
└── No → tasker-core-*

Are you building polyglot/multi-framework?
├── Yes → tasker-core-* (portable)
└── No → Either works
```

## What Each Package Provides

### Tasker Core (Foundation)

| Package | Provides |
|---------|----------|
| tasker-core-rb | Handler base classes, types, FFI bridge, domain events |
| tasker-core-py | Handler base classes, types, FFI bridge, domain events |
| tasker-core-ts | Handler base classes, types, FFI bridge, domain events |

**Use when:** You want the pure API, minimal dependencies, or framework independence.

### Tasker Contrib (Developer Experience)

| Package | Adds On Top of Core |
|---------|---------------------|
| tasker-contrib-rails | Railtie, generators, AS::Notifications bridge, RSpec helpers |
| tasker-contrib-fastapi | Lifespan integration, Pydantic models, pytest fixtures |
| tasker-contrib-bun | Bun.serve integration, TypeScript helpers |

**Use when:** You want batteries-included experience in your framework.

## Example: The Same Handler

### With tasker-core-rb only

```ruby
# Manual setup required
require 'tasker_core'

class PaymentHandler < TaskerCore::StepHandler::Base
  HANDLER_NAME = 'payment'
  
  def call(context)
    # Implementation
  end
end

# Manual registration
TaskerCore::HandlerRegistry.register(PaymentHandler)
```

### With tasker-contrib-rails

```bash
# Generated automatically
rails generate tasker:step_handler Payment --type api
```

```ruby
# config/initializers/tasker.rb (auto-configured)
Tasker.configure do |config|
  config.auto_discover_handlers = true
end
```

Both produce the same runtime behavior. Contrib adds developer ergonomics.
```

---

## Blog Examples: TAS-91 Update

The TAS-91 ticket should be updated to reflect the progressive disclosure approach:

### Ruby Examples (Reference)

**Location:** `tasker-core/workers/ruby/spec/handlers/examples/blog_examples/`

These are the **Core baseline** examples. They work without any framework.

### Contrib Examples (New)

**Location:** `tasker-contrib/examples/`

These show the **framework-enhanced** versions:

```
tasker-contrib/examples/
├── rails-ecommerce/              # Post 01 with Rails integration
│   ├── app/handlers/
│   ├── config/initializers/
│   └── README.md
├── fastapi-data-pipeline/        # Post 02 with FastAPI integration
│   ├── handlers/
│   ├── main.py
│   └── README.md
├── bun-microservices/            # Post 03 with Bun integration
│   ├── handlers/
│   ├── server.ts
│   └── README.md
└── ...
```

### GitBook Code Tabs

Where both Core and Contrib examples exist, use GitBook codetabs:

```markdown
{% codetabs name="Core (Pure)", type="ruby" %}
# tasker-core-rb only
class PaymentHandler < TaskerCore::StepHandler::Base
  # ...
end
{% codetabs name="Rails", type="ruby" %}
# With tasker-contrib-rails
# Generated via: rails g tasker:step_handler Payment
class PaymentHandler < TaskerCore::StepHandler::Api
  # ...
end
{% endcodetabs %}
```

---

## Updated Implementation Phases

| Phase | Effort | Description |
|-------|--------|-------------|
| **1: Foundation** | 2-3 days | Fresh gitbook, book.json, SUMMARY.md with new structure |
| **2: Disambiguation** | 1 day | Write choosing-your-stack.md, ecosystem overview |
| **3: Tooling** | 2 days | Dual-source sync (core + contrib), API generation |
| **4: Story Rewrites** | 5-7 days | Progressive disclosure pattern (Core → Contrib) |
| **5: New Content** | 3-4 days | Posts 06-08 |
| **6: Polish** | 1-2 days | Link validation, navigation |

**Total estimate:** 14-19 days

---

## Dependencies

| Ticket | Blocks | Notes |
|--------|--------|-------|
| TAS-112 | Post 05 (Observability) | Domain events for dual observability |
| TAS-91 | Story code tabs | Multi-language examples in Core |
| TAS-126 | Contrib docs sync | tasker-contrib structure exists |
| TAS-127 | CLI plugin docs | tasker-cli template generation |

---

## Open Questions

1. **Should TAS-91 create Contrib examples too, or separate ticket?**
   - Recommendation: TAS-91 stays Core-focused (27 handlers × 4 languages)
   - New ticket for Contrib example apps (full integration demos)

2. **Where does the gitbook repo live?**
   - Current: `tasker-gitbook` (separate repo)
   - Alternative: Move to `tasker-core/docs/gitbook/` or `tasker-contrib/docs/gitbook/`
   - Recommendation: Keep separate for now, easier CI

3. **API docs hosting?**
   - GitBook can embed, but generated docs are large
   - Alternative: Host on GitHub Pages, link from GitBook
   - Recommendation: Start embedded, extract if needed

---

## Success Criteria

- [ ] Users can find "which package do I need?" answer in < 30 seconds
- [ ] Each blog post shows Core foundation + Contrib enhancement (where applicable)
- [ ] Documentation syncs automatically from both repos
- [ ] API docs generated for Core (Rust, Ruby) from day one
- [ ] Clear progressive path: Learn → Implement → Enhance
