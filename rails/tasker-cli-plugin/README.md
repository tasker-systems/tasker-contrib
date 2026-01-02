# Rails CLI Plugin

Templates for `tasker-cli` to generate Ruby/Rails handlers and configurations.

## Structure

```
templates/
├── step_handler/           # Base step handler
├── step_handler_api/       # API handler with HTTP client
├── step_handler_decision/  # Decision handler for conditional workflows
├── step_handler_batchable/ # Batchable handler for large datasets
├── task_template/          # YAML task template
└── rails_initializer/      # Rails initializer template
```

## Usage

These templates are loaded by `tasker-cli` at runtime. Configure plugin discovery:

```toml
# .config/tasker-cli.toml
[profiles.development]
plugin-paths = ["~/projects/tasker-systems/tasker-contrib"]
```

Then generate:

```bash
tasker-cli template generate step-handler --name ProcessPayment --framework rails
```

## Status

🚧 In Development - Depends on TAS-127 (CLI plugin system)
