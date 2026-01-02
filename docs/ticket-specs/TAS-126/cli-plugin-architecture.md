# Tasker CLI Plugin Architecture

**Last Updated**: 2025-01-02
**Status**: Proposal
**Related**: [TAS-126](./README.md), tasker-core CLI

---

## Overview

The `tasker-cli` binary (in tasker-core) should be a stable, extensible tool that loads templates and plugins at runtime rather than requiring rebuilds for each new template or language addition.

This document proposes a plugin architecture inspired by [cargo-nextest](https://nexte.st/), which uses `.config/nextest.toml` for profiles and configuration.

---

## Problem Statement

### Current Implicit Model

```
tasker-core/
└── tasker-cli/
    └── src/
        └── templates/           # Templates compiled into binary
            ├── ruby/
            ├── python/
            └── typescript/
```

**Problems:**
1. Adding a new template requires rebuilding tasker-cli
2. Framework-specific templates couple Core to Contrib concerns
3. Users can't customize templates without forking
4. Version coordination: template updates require CLI releases

### Desired Model

```
tasker-cli (binary)
    │
    │ discovers at runtime
    ▼
┌─────────────────────────────────────────────────────────────┐
│                    TEMPLATE SOURCES                          │
├─────────────────────────────────────────────────────────────┤
│ 1. Built-in (minimal)     │ TOML config templates           │
│ 2. tasker-contrib plugins │ Language/framework templates    │
│ 3. User local overrides   │ .config/tasker-cli/templates/   │
│ 4. Project-level          │ ./tasker-cli/templates/         │
└─────────────────────────────────────────────────────────────┘
```

---

## Proposed Architecture

### Configuration File

Following nextest's pattern, tasker-cli would look for configuration in:

1. `.config/tasker-cli.toml` (user-level, in home directory)
2. `.tasker-cli.toml` (project-level, in repo root)
3. `tasker-cli.toml` (explicit path via `--config`)

```toml
# .config/tasker-cli.toml

[cli]
# Default profile to use
default-profile = "development"

[profiles.development]
# Local development settings
template-paths = [
    # Project-local templates (highest priority)
    "./tasker-cli/templates",
    # User-level customizations
    "~/.config/tasker-cli/templates",
]
plugin-paths = [
    # Local tasker-contrib checkout
    "~/projects/tasker-systems/tasker-contrib",
]

[profiles.ci]
# CI settings - use published plugins only
template-paths = []
plugin-paths = []
use-published-plugins = true

[profiles.production]
# Production - locked to specific versions
plugin-versions = { tasker-contrib-rails = "0.1.0" }
```

### Plugin Discovery

Plugins are directories containing a `tasker-plugin.toml` manifest:

```toml
# tasker-contrib/rails/tasker-cli-plugin/tasker-plugin.toml

[plugin]
name = "tasker-contrib-rails"
version = "0.1.0"
description = "Rails templates and generators for Tasker CLI"
languages = ["ruby"]
frameworks = ["rails"]

[templates]
# Template definitions
step-handler = { path = "templates/step_handler", languages = ["ruby"] }
step-handler-api = { path = "templates/step_handler_api", languages = ["ruby"] }
step-handler-decision = { path = "templates/step_handler_decision", languages = ["ruby"] }
step-handler-batchable = { path = "templates/step_handler_batchable", languages = ["ruby"] }
task-template = { path = "templates/task_template", languages = ["ruby"] }
rails-initializer = { path = "templates/rails_initializer", frameworks = ["rails"] }

[commands]
# Additional CLI commands provided by this plugin (future)
# rails-install = { handler = "commands/install.wasm" }  # WASM command extension?
```

### Template Format

Templates use a simple metadata + content structure:

```
tasker-contrib/rails/tasker-cli-plugin/
├── tasker-plugin.toml
└── templates/
    ├── step_handler/
    │   ├── template.toml        # Template metadata
    │   ├── handler.rb.tmpl      # Template content
    │   └── handler_spec.rb.tmpl
    ├── step_handler_api/
    │   ├── template.toml
    │   ├── handler.rb.tmpl
    │   └── handler_spec.rb.tmpl
    └── task_template/
        ├── template.toml
        └── task.yaml.tmpl
```

**template.toml:**
```toml
[template]
name = "step-handler"
description = "Generate a basic step handler"
version = "1.0.0"

[template.parameters]
name = { type = "string", required = true, description = "Handler class name" }
namespace = { type = "string", required = false, description = "Module namespace" }

[template.outputs]
handler = { path = "app/handlers/{{snake_case name}}_handler.rb", template = "handler.rb.tmpl" }
spec = { path = "spec/handlers/{{snake_case name}}_handler_spec.rb", template = "handler_spec.rb.tmpl" }
```

**handler.rb.tmpl:**
```ruby
# frozen_string_literal: true

{{#if namespace}}
module {{namespace}}
{{/if}}
class {{pascal_case name}}Handler < TaskerCore::StepHandler::Base
  HANDLER_NAME = '{{snake_case name}}'
  HANDLER_VERSION = '1.0.0'

  def call(context)
    # TODO: Implement handler logic
    success(result: {})
  end
end
{{#if namespace}}
end
{{/if}}
```

### Template Engine

The CLI would use a simple template engine (likely [Handlebars](https://handlebarsjs.com/) or [Tera](https://keats.github.io/tera/) for Rust) with built-in helpers:

| Helper | Example | Output |
|--------|---------|--------|
| `snake_case` | `{{snake_case "ProcessPayment"}}` | `process_payment` |
| `pascal_case` | `{{pascal_case "process_payment"}}` | `ProcessPayment` |
| `camel_case` | `{{camel_case "process_payment"}}` | `processPayment` |
| `kebab_case` | `{{kebab_case "ProcessPayment"}}` | `process-payment` |
| `upper_case` | `{{upper_case "name"}}` | `NAME` |

---

## Updated Repository Structure

```
tasker-contrib/
├── rails/
│   ├── tasker-contrib-rails/     # Ruby gem (Railtie, generators)
│   ├── tasker-cli-plugin/        # CLI plugin (templates)
│   │   ├── tasker-plugin.toml
│   │   └── templates/
│   │       ├── step_handler/
│   │       ├── step_handler_api/
│   │       ├── task_template/
│   │       └── rails_initializer/
│   └── tasker-rails-template/    # Full app template
│
├── python/
│   ├── tasker-contrib-fastapi/   # Python package
│   ├── tasker-cli-plugin/        # CLI plugin
│   │   ├── tasker-plugin.toml
│   │   └── templates/
│   └── tasker-fastapi-template/
│
├── typescript/
│   ├── tasker-contrib-express/   # npm package
│   ├── tasker-cli-plugin/        # CLI plugin
│   │   ├── tasker-plugin.toml
│   │   └── templates/
│   └── tasker-express-template/
│
└── rust/
    ├── tasker-contrib-axum/      # Rust crate
    ├── tasker-cli-plugin/        # CLI plugin
    │   ├── tasker-plugin.toml
    │   └── templates/
    └── tasker-axum-template/
```

### Plugin Discovery Paths

The CLI discovers plugins from multiple sources:

```
Priority (highest to lowest):
1. --plugin-path CLI argument
2. Project-level: ./.tasker-cli/plugins/
3. Config file paths: plugin-paths in tasker-cli.toml
4. User-level: ~/.config/tasker-cli/plugins/
5. System-level: /usr/local/share/tasker-cli/plugins/
6. Published plugins (fetched from registry)
```

---

## CLI Commands

### Template Generation

```bash
# List available templates (from all discovered plugins)
tasker-cli template list
# Output:
# TEMPLATE                  PLUGIN                  LANGUAGES    FRAMEWORKS
# step-handler              tasker-contrib-rails    ruby         -
# step-handler-api          tasker-contrib-rails    ruby         -
# step-handler              tasker-contrib-fastapi  python       -
# step-handler              tasker-contrib-express  typescript   -

# Generate with specific template
tasker-cli template generate step-handler \
  --name ProcessPayment \
  --language ruby \
  --output ./app/handlers/

# Generate with framework hint (selects appropriate plugin)
tasker-cli template generate step-handler \
  --name ProcessPayment \
  --framework rails \
  --output ./app/handlers/

# List templates for a specific language
tasker-cli template list --language python
```

### Plugin Management

```bash
# List discovered plugins
tasker-cli plugin list
# Output:
# PLUGIN                  VERSION  SOURCE              STATUS
# tasker-contrib-rails    0.1.0    ~/projects/...      local
# tasker-contrib-fastapi  0.1.0    registry            installed
# tasker-contrib-express  -        -                   not installed

# Install plugin from registry (future)
tasker-cli plugin install tasker-contrib-rails

# Show plugin details
tasker-cli plugin info tasker-contrib-rails

# Validate plugin structure
tasker-cli plugin validate ./rails/tasker-cli-plugin/
```

### Profile Management

```bash
# List profiles
tasker-cli profile list

# Use specific profile
tasker-cli --profile ci template generate ...

# Show effective configuration
tasker-cli config show --profile development
```

---

## Implementation Phases

### Phase 1: Core Plugin Loading (tasker-core)

**Ticket needed in tasker-core**

- [ ] Configuration file loading (`.config/tasker-cli.toml`)
- [ ] Plugin discovery from filesystem paths
- [ ] Plugin manifest parsing (`tasker-plugin.toml`)
- [ ] Template listing command
- [ ] Basic template generation with Tera/Handlebars

### Phase 2: Contrib Plugin Structure (tasker-contrib)

- [ ] Create `rails/tasker-cli-plugin/` with manifest
- [ ] Migrate handler templates from conceptual to actual
- [ ] Validate plugin structure works with CLI

### Phase 3: Generator Integration

- [ ] Rails generators call `tasker-cli template generate`
- [ ] Pass-through parameters from `rails g tasker:*`
- [ ] Handle output path conventions

### Phase 4: Registry (Future)

- [ ] Plugin registry (GitHub releases? Dedicated registry?)
- [ ] `tasker-cli plugin install` command
- [ ] Version pinning and lockfiles
- [ ] Checksum verification

---

## Design Decisions

### Why Not Compiled-In Templates?

| Compiled-In | Runtime Loaded |
|-------------|----------------|
| Fast startup | Slightly slower first load |
| No external dependencies | Requires plugin files |
| Version locked to CLI | Templates update independently |
| Hard to customize | Easy local overrides |
| Rebuild for changes | Hot reload possible |

**Decision:** Runtime loaded templates with optional caching.

### Why TOML for Plugin Manifests?

- Consistent with tasker-core configuration
- Human-readable and editable
- Good Rust library support (toml crate)
- Not as verbose as YAML for structured data

### Why Handlebars/Tera for Templates?

- Logic-less or minimal-logic templates
- Well-understood syntax
- Good Rust implementations
- Familiar to web developers

### Why Not WASM for Command Extensions?

WASM could allow plugins to extend CLI commands (not just templates). Deferred because:
- Adds significant complexity
- Template generation covers 90% of use cases
- Can add later without breaking changes

---

## Relationship to Framework Generators

Framework generators (like `rails g tasker:step_handler`) become thin wrappers:

```ruby
# In tasker-contrib-rails gem
class StepHandlerGenerator < Rails::Generators::NamedBase
  def generate_handler
    # Delegate to tasker-cli
    system(
      "tasker-cli", "template", "generate", "step-handler",
      "--name", file_name,
      "--language", "ruby",
      "--framework", "rails",
      "--output", destination_root
    )
  end

  def customize_for_rails
    # Rails-specific post-processing
    # - Add to autoload paths
    # - Register in application config
    # - etc.
  end
end
```

Benefits:
- Templates are single-source-of-truth (in plugin)
- Generators add framework-specific glue
- Updates to templates don't require gem releases

---

## Open Questions

### 1. Plugin Distribution

How do users get plugins?

**Options:**
- A) Git clone tasker-contrib, configure paths
- B) Download releases from GitHub
- C) Dedicated plugin registry
- D) Bundled with language packages (gem includes plugin)

**Recommendation:** Start with A+B, consider D for convenience.

### 2. Template Versioning

Should templates have independent versions from plugins?

**Recommendation:** No, keep it simple. Plugin version = all template versions.

### 3. Template Testing

How do we test templates produce valid code?

**Recommendation:** 
- Snapshot testing for template output
- Integration tests that generate + compile/lint
- Example outputs in plugin for reference

---

## Related Documents

- [README.md](../../../README.md) - Repository overview
- [rails.md](./rails.md) - Rails integration (uses plugin templates)
- tasker-core CLI documentation (future)
