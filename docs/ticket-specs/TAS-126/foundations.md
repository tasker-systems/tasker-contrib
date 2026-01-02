# TAS-126: Architectural Foundations

**Last Updated**: 2025-01-02
**Status**: Reference Document
**Linear**: [TAS-126](https://linear.app/tasker-systems/issue/TAS-126)

---

## Purpose

This document provides deeper architectural context for the tasker-contrib ecosystem. For the high-level vision and repository structure, see the [main README](../../../README.md).

---

## Design Rationale

### Why Separate Repositories?

**Option Considered: Monorepo (contrib in tasker-core)**

Pros:
- Single clone for everything
- Atomic cross-package changes
- Unified versioning

Cons:
- Core becomes coupled to framework dependencies
- Larger clone for users who only want one integration
- Framework-specific CI slows down Core CI
- Harder to accept community contributions without Core review

**Decision: Separate Repository**

The tasker-contrib repository allows:
- Core to remain framework-agnostic
- Independent release cycles
- Lower barrier for community contributions
- Framework teams can own their integrations

### Why Not Full Rails Engine?

The legacy `tasker-engine` was a full Rails Engine with:
- Mounted routes
- ActiveRecord models
- Own migrations
- Isolated namespace

**Problems with this approach:**
1. **State ownership conflict**: Both tasker-core (Rust/PostgreSQL) and Rails Engine wanted to own state
2. **Migration conflicts**: Two migration systems for the same tables
3. **API duplication**: Engine had GraphQL, Core has Axum API
4. **Complexity**: Full Engine when most apps just need handlers

**Decision: Railtie First**

`tasker-contrib-rails` starts as a Railtie:
- Hooks into Rails lifecycle without owning routes
- Provides generators without owning models
- Bridges events without duplicating them
- Can evolve to Engine later if needed

---

## Framework Integration Patterns

### Pattern: Lifecycle Integration

Each framework has a different lifecycle model. Contrib packages adapt to these.

**Rails (Railtie initializers):**
```ruby
class Railtie < Rails::Railtie
  initializer 'tasker.bootstrap', after: :load_config_initializers do
    TaskerCore::Worker::Bootstrap.start!
  end
end
```

**FastAPI (lifespan context manager):**
```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    bootstrap = Bootstrap.start()
    yield
    bootstrap.shutdown()
```

**Express (middleware + process signals):**
```typescript
const bootstrap = Bootstrap.start();
process.on('SIGTERM', () => bootstrap.shutdown());
```

**Axum (state extractor):**
```rust
let state = AppState { tasker: Bootstrap::start() };
let app = Router::new().with_state(state);
```

### Pattern: Event Bridge

Domain events from tasker-core need to integrate with framework observability.

**Rails → ActiveSupport::Notifications:**
```ruby
class ActiveSupportAdapter < TaskerCore::DomainEvents::BaseSubscriber
  def handle(event)
    ActiveSupport::Notifications.instrument(
      "tasker.#{event.event_type}",
      event.payload
    )
  end
end
```

**FastAPI → Structured Logging:**
```python
class LoggingSubscriber(BaseSubscriber):
    def handle(self, event: DomainEvent):
        structlog.get_logger().info(
            "tasker_event",
            event_type=event.event_type,
            **event.payload
        )
```

**Express → EventEmitter:**
```typescript
class EventEmitterBridge extends BaseSubscriber {
  handle(event: DomainEvent) {
    this.emitter.emit(`tasker:${event.eventType}`, event.payload);
  }
}
```

### Pattern: Generator Wrapping

Framework generators wrap `tasker-cli` for consistency:

```ruby
# Rails generator
class StepHandlerGenerator < Rails::Generators::NamedBase
  def create_handler
    # Delegate to tasker-cli for template generation
    system("tasker-cli template generate " \
           "--type step-handler " \
           "--name #{file_name} " \
           "--language ruby " \
           "--output #{handler_path}")
  end
  
  def create_spec
    # Rails-specific test template (RSpec conventions)
    template 'step_handler_spec.rb.erb', spec_path
  end
end
```

This pattern means:
- Handler templates are consistent across frameworks (tasker-cli)
- Test templates follow framework conventions (framework-specific)
- Updates to handler structure propagate automatically

---

## Configuration Architecture

### Three-Layer Configuration

```
┌─────────────────────────────────────────────────────────────┐
│                    FRAMEWORK LAYER                           │
│  Rails initializer, FastAPI settings, Express config         │
│  - Framework-idiomatic syntax                                │
│  - Environment-based (Rails.env, FASTAPI_ENV)               │
│  - Translates to TOML or environment variables               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    TOML LAYER                                │
│  config/tasker/base/*.toml                                  │
│  config/tasker/environments/{env}/*.toml                    │
│  - Tasker-native configuration                              │
│  - Validated by tasker-cli                                  │
│  - Loaded by Rust foundation                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    RUST RUNTIME                              │
│  ConfigurationManager in tasker-shared                      │
│  - Merges base + environment                                │
│  - Substitutes environment variables                        │
│  - Provides to worker and orchestration                     │
└─────────────────────────────────────────────────────────────┘
```

### Framework Config DSL Design

Framework DSLs should:
1. Feel native to the framework
2. Map cleanly to TOML structure
3. Not invent new semantics

**Good (Maps to TOML):**
```ruby
Tasker.configure do |config|
  config.database.pool_size = 20      # → [database.pool] max_connections = 20
  config.worker.polling_interval = 10 # → [polling] interval_ms = 10
end
```

**Bad (Invents new concepts):**
```ruby
Tasker.configure do |config|
  config.magic_mode = true        # What TOML key is this?
  config.rails_integration = :full # Tasker doesn't know about Rails
end
```

---

## Testing Architecture

### Test Levels

```
┌─────────────────────────────────────────────────────────────┐
│                    UNIT TESTS                                │
│  - Test contrib code in isolation                           │
│  - Mock tasker-core interfaces                              │
│  - Fast, no database required                               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    INTEGRATION TESTS                         │
│  - Test contrib + tasker-core together                      │
│  - Real FFI calls, real database                            │
│  - Use dummy/example apps                                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    E2E TESTS                                 │
│  - Full workflow execution                                  │
│  - Test template apps work                                  │
│  - Deployment smoke tests                                   │
└─────────────────────────────────────────────────────────────┘
```

### Test Helpers Design

Each Contrib package provides framework-idiomatic test helpers:

**Ruby (RSpec):**
```ruby
RSpec.describe MyHandler do
  include TaskerContribRails::Testing::RSpecHelpers
  
  let(:context) { build_step_context(task_fields: { 'order_id' => '123' }) }
  
  it 'processes successfully' do
    result = handler.call(context)
    expect(result).to be_success
    expect(result).to have_result_data(status: 'processed')
  end
end
```

**Python (pytest):**
```python
from tasker_contrib_fastapi.testing import step_context

def test_handler_success(step_context):
    context = step_context(task_fields={'order_id': '123'})
    result = handler.call(context)
    assert result.is_success()
    assert result.result_data['status'] == 'processed'
```

**TypeScript (Jest/Vitest):**
```typescript
import { buildStepContext } from 'tasker-contrib-express/testing';

test('handler processes successfully', async () => {
  const context = buildStepContext({ taskFields: { orderId: '123' } });
  const result = await handler.call(context);
  expect(result.isSuccess()).toBe(true);
  expect(result.resultData.status).toBe('processed');
});
```

---

## Versioning Strategy

### Independent Versions

Each Contrib package versions independently:

```
tasker-core-rb      0.5.0
tasker-contrib-rails 0.1.0  (depends on tasker-core-rb ~> 0.5.0)
tasker-contrib-rails 0.2.0  (depends on tasker-core-rb ~> 0.5.0)
tasker-core-rb      0.6.0  (breaking change)
tasker-contrib-rails 0.3.0  (depends on tasker-core-rb ~> 0.6.0)
```

### Compatibility Matrix

Each Contrib package documents compatibility:

| tasker-contrib-rails | tasker-core-rb | Rails | Ruby |
|---------------------|----------------|-------|------|
| 0.1.x | 0.5.x | 7.0-7.2 | 3.2+ |
| 0.2.x | 0.5.x-0.6.x | 7.0-7.2 | 3.2+ |
| 0.3.x | 0.6.x+ | 7.1-8.0 | 3.2+ |

### Breaking Changes

Contrib packages follow semver:
- **Patch**: Bug fixes, documentation
- **Minor**: New features, new generators, deprecations
- **Major**: Breaking API changes, dropped framework versions

---

## Future Considerations

### Plugin Architecture

As the ecosystem grows, we may want plugins within Contrib:

```
tasker-contrib-rails/
├── core/           # Base Railtie, essential generators
├── activejob/      # ActiveJob adapter (opt-in)
├── actioncable/    # Real-time updates (opt-in)
└── administrate/   # Admin dashboard (opt-in)
```

### Shared Infrastructure

Some operational tooling might be shared:

```
ops/
├── shared/
│   ├── postgres/        # PostgreSQL + PGMQ setup
│   └── observability/   # Common metrics, traces
├── helm/
│   └── ...
└── terraform/
    └── ...
```

### tasker-cli Extensions

`tasker-cli` might support Contrib-specific commands:

```bash
# Core command
tasker-cli template generate --type step-handler

# Contrib extension (future)
tasker-cli contrib rails install
tasker-cli contrib rails generate handler
```

---

## Related Documents

- [README.md](../../../README.md) - Repository overview and structure
- [DEVELOPMENT.md](../../../DEVELOPMENT.md) - Local development setup
- [rails.md](./rails.md) - Rails-specific implementation details
- [cli-plugin-architecture.md](./cli-plugin-architecture.md) - CLI plugin system design
