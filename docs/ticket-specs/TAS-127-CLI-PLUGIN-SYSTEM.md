# TAS-127: Tasker CLI Plugin System

## Summary

Extend `tasker-cli` to load templates from external plugins at runtime, rather than having templates compiled into the binary. This enables tasker-contrib to provide framework-specific templates without requiring tasker-core releases.

## Background

Currently, any template generation would require templates to be compiled into the `tasker-cli` binary. This creates several problems:

1. **Coupling**: Core must know about all framework templates
2. **Release coordination**: Template updates require CLI releases
3. **Customization**: Users can't override or add templates
4. **Bloat**: CLI binary grows with every framework added

The solution is a plugin architecture inspired by [cargo-nextest](https://nexte.st/), where configuration and plugins are discovered at runtime.

## Design

### Configuration File

The CLI discovers configuration from (in priority order):

1. `--config` CLI argument
2. `.tasker-cli.toml` (project-level)
3. `~/.config/tasker-cli.toml` (user-level)

```toml
# .config/tasker-cli.toml

[cli]
default-profile = "development"

[profiles.development]
# Local development: point to local tasker-contrib checkout
plugin-paths = [
    "./tasker-cli-plugins",
    "~/projects/tasker-systems/tasker-contrib",
]

[profiles.ci]
# CI: use published plugins only
plugin-paths = []
use-published-plugins = true

[profiles.production]
# Production: locked versions
plugin-versions = { tasker-contrib-rails = "0.1.0" }
```

### Plugin Discovery

Plugins are directories containing a `tasker-plugin.toml` manifest:

```toml
# tasker-plugin.toml

[plugin]
name = "tasker-contrib-rails"
version = "0.1.0"
description = "Rails templates for Tasker CLI"
languages = ["ruby"]
frameworks = ["rails"]

[templates]
step-handler = { path = "templates/step_handler", languages = ["ruby"] }
step-handler-api = { path = "templates/step_handler_api", languages = ["ruby"] }
step-handler-decision = { path = "templates/step_handler_decision", languages = ["ruby"] }
step-handler-batchable = { path = "templates/step_handler_batchable", languages = ["ruby"] }
task-template = { path = "templates/task_template", languages = ["ruby"] }
rails-initializer = { path = "templates/rails_initializer", frameworks = ["rails"] }
```

### Template Format

Templates use [Tera](https://keats.github.io/tera/) (Jinja2-like syntax for Rust):

```
templates/step_handler/
├── template.toml        # Template metadata
├── handler.rb.tera      # Template content
└── handler_spec.rb.tera # Optional additional files
```

**template.toml**:
```toml
[template]
name = "step-handler"
description = "Generate a basic step handler"
version = "1.0.0"

[parameters]
name = { type = "string", required = true }
namespace = { type = "string", required = false }
handler_type = { type = "string", default = "base", enum = ["base", "api", "decision", "batchable"] }

[outputs]
handler = { path = "app/handlers/{{ name | snake_case }}_handler.rb", template = "handler.rb.tera" }
spec = { path = "spec/handlers/{{ name | snake_case }}_handler_spec.rb", template = "handler_spec.rb.tera", optional = true }
```

**handler.rb.tera**:
```ruby
# frozen_string_literal: true

{% if namespace %}
module {{ namespace }}
{% endif %}
class {{ name | pascal_case }}Handler < TaskerCore::StepHandler::Base
{% if handler_type == "api" %}
  include TaskerCore::StepHandler::Mixins::Api
{% elif handler_type == "decision" %}
  include TaskerCore::StepHandler::Mixins::Decision
{% elif handler_type == "batchable" %}
  include TaskerCore::StepHandler::Mixins::Batchable
{% endif %}

  HANDLER_NAME = '{{ name | snake_case }}'
  HANDLER_VERSION = '1.0.0'

  def call(context)
    # TODO: Implement handler logic
    success(result: {})
  end
end
{% if namespace %}
end
{% endif %}
```

### CLI Commands

```bash
# List available templates from all discovered plugins
tasker-cli template list
# TEMPLATE              PLUGIN                  LANGUAGES    FRAMEWORKS
# step-handler          tasker-contrib-rails    ruby         -
# step-handler-api      tasker-contrib-rails    ruby         -
# step-handler          tasker-contrib-python   python       -

# Generate with parameters
tasker-cli template generate step-handler \
  --name ProcessPayment \
  --language ruby \
  --framework rails \
  --handler-type api \
  --output ./app/handlers/

# Show template details
tasker-cli template info step-handler --plugin tasker-contrib-rails

# List discovered plugins
tasker-cli plugin list

# Validate a plugin
tasker-cli plugin validate ./path/to/plugin

# Show effective configuration
tasker-cli config show --profile development
```

### Plugin Discovery Order

1. `--plugin-path` CLI argument (highest priority)
2. Project-level: `./.tasker-cli/plugins/`
3. Config file `plugin-paths`
4. User-level: `~/.config/tasker-cli/plugins/`
5. System-level: `/usr/local/share/tasker-cli/plugins/`

### Built-in Templates

The CLI should have minimal built-in templates for TOML configuration files only:

- `common.toml` - Base configuration template
- `worker.toml` - Worker configuration template

All handler templates live in tasker-contrib plugins.

## Implementation Plan

### Phase 1: Configuration Loading
- [ ] Add `config` module to tasker-cli
- [ ] Implement TOML config file discovery
- [ ] Implement profile system
- [ ] Add `tasker-cli config show` command

### Phase 2: Plugin Discovery
- [ ] Add `plugin` module
- [ ] Implement plugin path scanning
- [ ] Parse `tasker-plugin.toml` manifests
- [ ] Add `tasker-cli plugin list` command
- [ ] Add `tasker-cli plugin validate` command

### Phase 3: Template System
- [ ] Add Tera dependency
- [ ] Implement template loading from plugins
- [ ] Implement parameter parsing and validation
- [ ] Add built-in Tera filters: `snake_case`, `pascal_case`, `camel_case`, `kebab_case`
- [ ] Add `tasker-cli template list` command
- [ ] Add `tasker-cli template generate` command

### Phase 4: Integration
- [ ] Update existing `tasker-cli` commands to use new config system
- [ ] Add `--profile` flag to all commands
- [ ] Documentation

## Technical Details

### Dependencies

```toml
# Cargo.toml additions
tera = "1.19"
toml = "0.8"  # Already present
directories = "5.0"  # For XDG paths
```

### Module Structure

```
tasker-cli/src/
├── commands/
│   ├── config.rs      # Config commands
│   ├── plugin.rs      # Plugin commands
│   ├── template.rs    # Template commands (new)
│   └── ...
├── config/
│   ├── mod.rs
│   ├── loader.rs      # Config file discovery
│   └── profiles.rs    # Profile system
├── plugins/
│   ├── mod.rs
│   ├── discovery.rs   # Plugin scanning
│   ├── manifest.rs    # Plugin manifest parsing
│   └── registry.rs    # Plugin registry
├── templates/
│   ├── mod.rs
│   ├── engine.rs      # Tera wrapper
│   ├── loader.rs      # Template loading
│   └── filters.rs     # Custom Tera filters
└── ...
```

## Acceptance Criteria

- [ ] `tasker-cli config show` displays effective configuration
- [ ] `tasker-cli plugin list` shows discovered plugins
- [ ] `tasker-cli plugin validate` validates plugin structure
- [ ] `tasker-cli template list` shows available templates
- [ ] `tasker-cli template generate` creates files from templates
- [ ] Plugins from tasker-contrib are discoverable when configured
- [ ] Profile system allows dev/ci/production configurations
- [ ] Documentation updated

## Blocks

- TAS-126 (tasker-contrib): Framework generators depend on this

## Related

- tasker-contrib CLI plugin architecture: `docs/ticket-specs/TAS-126/cli-plugin-architecture.md`
- Tera documentation: https://keats.github.io/tera/
- cargo-nextest config: https://nexte.st/book/configuration.html
