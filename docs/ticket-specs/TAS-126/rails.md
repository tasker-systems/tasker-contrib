# TAS-126: Rails Integration (tasker-contrib-rails)

**Last Updated**: 2025-01-02
**Status**: Planning
**Priority**: High
**Linear**: [TAS-126](https://linear.app/tasker-systems/issue/TAS-126)

---

## Overview

This document specifies the implementation of `tasker-contrib-rails`, the first framework integration package in the Tasker Contrib ecosystem. Rails is the priority target because:

1. Many teams Pete supports use Rails "majestic monolith" architectures
2. The legacy `tasker-engine` provides a reference implementation to learn from
3. Rails developers have strong expectations for "the Rails way" integration
4. Success here establishes patterns for other framework integrations

---

## Background: Legacy tasker-engine Analysis

The original `tasker-engine` (never released) provided:

### Worth Extracting → tasker-contrib-rails

| Feature | Legacy Location | Value |
|---------|-----------------|-------|
| Task handler generator | `lib/generators/tasker/task_handler_generator.rb` | Scaffolds handlers + YAML + specs |
| Subscriber generator | `lib/generators/tasker/subscriber_generator.rb` | Scaffolds event subscribers |
| Config initializer template | `lib/generators/tasker/templates/initialize.rb.erb` | Bootstrap configuration |
| ERB templates | `lib/generators/tasker/templates/*.erb` | Handler, spec, config scaffolds |

### Superseded by Tasker Core (Do NOT Extract)

| Feature | Rationale |
|---------|-----------|
| ActiveRecord models | Tasker Core owns state via Rust/PostgreSQL |
| Statesman state machines | Rust orchestration handles state transitions |
| GraphQL API | tasker-orchestration provides API |
| Handler base classes | Already in tasker-core-rb |
| Event catalog | Managed by Rust orchestration |
| Dry-events system | Replaced by FFI domain events |

---

## Architecture

### Package Structure

```
rails/
├── tasker-contrib-rails/           # Ruby gem
│   ├── lib/
│   │   ├── tasker_contrib_rails.rb       # Main entry point
│   │   └── tasker_contrib_rails/
│   │       ├── version.rb
│   │       ├── railtie.rb                # Rails integration hooks
│   │       ├── configuration.rb          # Rails-style config DSL
│   │       ├── generators/
│   │       │   ├── install_generator.rb  # rails g tasker:install
│   │       │   ├── step_handler_generator.rb
│   │       │   └── task_template_generator.rb
│   │       ├── event_bridge/
│   │       │   ├── active_support_adapter.rb
│   │       │   └── subscriber_bridge.rb
│   │       └── testing/
│   │           └── rspec_helpers.rb      # RSpec matchers
│   ├── spec/
│   │   ├── railtie_spec.rb
│   │   ├── generators/
│   │   ├── event_bridge/
│   │   └── dummy/                        # Rails dummy app for testing
│   ├── Gemfile
│   ├── Rakefile
│   ├── README.md
│   ├── CHANGELOG.md
│   └── tasker-contrib-rails.gemspec
│
└── tasker-cli-plugin/              # CLI plugin (templates)
    ├── tasker-plugin.toml            # Plugin manifest
    └── templates/
        ├── step_handler/
        │   ├── template.toml
        │   ├── handler.rb.tmpl
        │   └── handler_spec.rb.tmpl
        ├── step_handler_api/
        ├── step_handler_decision/
        ├── step_handler_batchable/
        ├── task_template/
        └── rails_initializer/
```

**Note:** The `tasker-cli-plugin/` directory contains templates that `tasker-cli` loads at runtime. The gem's generators are thin wrappers that call `tasker-cli template generate`. See [CLI Plugin Architecture](./cli-plugin-architecture.md) for details.

### Dependency Graph

```
┌─────────────────────────────┐
│     Your Rails App          │
│  (Rails 7.0+, Ruby 3.2+)    │
└─────────────────────────────┘
              │
              ▼
┌─────────────────────────────┐
│   tasker-contrib-rails      │
│   - Railtie                 │
│   - Generators              │
│   - Event Bridge            │
└─────────────────────────────┘
              │
              ▼
┌─────────────────────────────┐
│     tasker-core-rb          │
│   - Handler classes         │
│   - FFI bridge              │
│   - Domain events           │
└─────────────────────────────┘
              │
              ▼
┌─────────────────────────────┐
│   Rust FFI Extension        │
│   (tasker_worker_rb.so)     │
└─────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Foundation (This Ticket)

**Deliverables:**
1. Gem skeleton with Railtie
2. Install generator
3. Step handler generator
4. Basic AS::Notification bridge
5. Documentation

**Estimated Effort:** 2-3 days

### Phase 2: Enhanced Generators

**Deliverables:**
1. Task template generator
2. Decision handler generator
3. Batchable handler generator
4. Subscriber generator
5. CLI integration (generators call `tasker-cli template generate`)

**Note:** This phase depends on the CLI plugin system being implemented in tasker-core. See [CLI Plugin Architecture](./cli-plugin-architecture.md) for the design. The `rails/tasker-cli-plugin/` directory provides the templates that `tasker-cli` loads at runtime.

**Estimated Effort:** 2 days (after CLI plugin system is ready)

### Phase 3: Testing & Polish

**Deliverables:**
1. RSpec helpers/matchers
2. Dummy Rails app for integration testing
3. CI pipeline
4. Published to RubyGems

**Estimated Effort:** 2 days

### Phase 4: Advanced Features (Future)

**Deliverables:**
1. ActiveJob adapter (opt-in)
2. Rich event types
3. GoodJob deployment pattern
4. Engine with optional routes

---

## Detailed Specifications

### 1. Railtie

The Railtie provides Rails integration without forcing structure:

```ruby
# lib/tasker_contrib_rails/railtie.rb
module TaskerContribRails
  class Railtie < Rails::Railtie
    # Configuration namespace
    config.tasker = ActiveSupport::OrderedOptions.new

    # Bootstrap tasker-core-rb on Rails initialization
    initializer 'tasker.bootstrap', after: :load_config_initializers do |app|
      if TaskerContribRails.worker_enabled?
        TaskerCore::Worker::Bootstrap.start!
        
        # Wire up event bridge if configured
        if app.config.tasker.event_bridge_enabled
          TaskerContribRails::EventBridge::ActiveSupportAdapter.install!
        end
      end
    end

    # Register generators
    generators do
      require 'tasker_contrib_rails/generators/install_generator'
      require 'tasker_contrib_rails/generators/step_handler_generator'
      require 'tasker_contrib_rails/generators/task_template_generator'
    end

    # Provide rake tasks
    rake_tasks do
      load 'tasker_contrib_rails/tasks/tasker.rake'
    end

    # Graceful shutdown
    config.after_initialize do
      at_exit do
        TaskerCore::Worker::Bootstrap.shutdown! if TaskerContribRails.worker_enabled?
      end
    end
  end
end
```

**Configuration Options:**

```ruby
# config/application.rb or config/environments/*.rb
config.tasker.worker_enabled = ENV.fetch('TASKER_WORKER_ENABLED', false)
config.tasker.event_bridge_enabled = true
config.tasker.handler_paths = ['app/handlers']
config.tasker.template_paths = ['config/tasker/templates']
```

### 2. Install Generator

```bash
rails generate tasker:install
```

**Creates:**

```
config/
├── initializers/
│   └── tasker.rb              # Tasker configuration
└── tasker/
    ├── base/
    │   ├── common.toml        # Shared configuration
    │   └── worker.toml        # Worker configuration
    └── templates/
        └── .gitkeep           # Task template directory

app/
└── handlers/
    └── .gitkeep               # Handler directory
```

**config/initializers/tasker.rb:**

```ruby
# Tasker Configuration
# See: https://github.com/tasker-systems/tasker-contrib/docs/rails.md

Rails.application.config.tasker.tap do |tasker|
  # Enable worker in this process (typically false for web, true for worker)
  tasker.worker_enabled = ENV.fetch('TASKER_WORKER_ENABLED', 'false') == 'true'

  # Bridge domain events to ActiveSupport::Notifications
  tasker.event_bridge_enabled = true

  # Handler discovery paths (relative to Rails.root)
  tasker.handler_paths = ['app/handlers']

  # Task template paths (relative to Rails.root)
  tasker.template_paths = ['config/tasker/templates']
end

# Configure tasker-core-rb
TaskerCore.configure do |config|
  # Configuration is primarily via TOML files in config/tasker/
  # This block is for runtime overrides only
  
  # Example: Override database URL from Rails credentials
  # config.database_url = Rails.application.credentials.dig(:tasker, :database_url)
end
```

### 3. Step Handler Generator

```bash
rails generate tasker:step_handler ProcessPayment --type api
rails generate tasker:step_handler AnalyzeBatch --type batchable
rails generate tasker:step_handler RouteOrder --type decision
```

**Options:**

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `--type` | `base`, `api`, `decision`, `batchable` | `base` | Handler type |
| `--namespace` | string | none | Module namespace |
| `--skip-spec` | flag | false | Skip spec generation |

**Generator Implementation (Phase 2):**

Once the CLI plugin system is ready, generators delegate to `tasker-cli`:

```ruby
# lib/tasker_contrib_rails/generators/step_handler_generator.rb
class StepHandlerGenerator < Rails::Generators::NamedBase
  class_option :type, type: :string, default: 'base'
  class_option :namespace, type: :string
  class_option :skip_spec, type: :boolean, default: false

  def generate_handler
    template_name = options[:type] == 'base' ? 'step-handler' : "step-handler-#{options[:type]}"
    
    # Delegate to tasker-cli (templates come from rails/tasker-cli-plugin/)
    system(
      "tasker-cli", "template", "generate", template_name,
      "--name", file_name,
      "--language", "ruby",
      "--framework", "rails",
      "--output", Rails.root.to_s,
      *(options[:namespace] ? ["--namespace", options[:namespace]] : []),
      *(options[:skip_spec] ? ["--skip-spec"] : [])
    )
  end

  def add_to_registry
    # Rails-specific: ensure handler is discoverable
    # This is framework glue that doesn't belong in the template
  end
end
```

**Generated Files (from `rails/tasker-cli-plugin/templates/step_handler_api/`):**

```ruby
# app/handlers/process_payment_handler.rb
# frozen_string_literal: true

class ProcessPaymentHandler < TaskerCore::StepHandler::Base
  include TaskerCore::StepHandler::Mixins::Api

  # Handler metadata for registration
  HANDLER_NAME = 'process_payment'
  HANDLER_VERSION = '1.0.0'

  def call(context)
    # Access task context
    order_id = context.get_task_field('order_id')
    amount = context.get_task_field('amount')

    # Make API call using the Api mixin
    response = post('/payments/charge', body: {
      order_id: order_id,
      amount: amount
    })

    if response[:status] == 200
      success(
        result: {
          payment_id: response[:body]['payment_id'],
          status: 'charged'
        }
      )
    else
      error(
        error_type: TaskerCore::Types::ErrorTypes::EXTERNAL_SERVICE_ERROR,
        message: "Payment failed: #{response[:body]['error']}"
      )
    end
  end

  private

  def base_url
    ENV.fetch('PAYMENT_SERVICE_URL', 'https://api.payments.example.com')
  end
end
```

```ruby
# spec/handlers/process_payment_handler_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessPaymentHandler do
  include TaskerContribRails::Testing::RSpecHelpers

  let(:handler) { described_class.new }
  let(:context) { build_step_context(task_fields: { 'order_id' => '123', 'amount' => 99.99 }) }

  describe '#call' do
    context 'when payment succeeds' do
      before do
        stub_request(:post, 'https://api.payments.example.com/payments/charge')
          .to_return(status: 200, body: { payment_id: 'pay_abc123' }.to_json)
      end

      it 'returns success with payment_id' do
        result = handler.call(context)

        expect(result).to be_success
        expect(result.result_data[:payment_id]).to eq('pay_abc123')
      end
    end

    context 'when payment fails' do
      before do
        stub_request(:post, 'https://api.payments.example.com/payments/charge')
          .to_return(status: 400, body: { error: 'Insufficient funds' }.to_json)
      end

      it 'returns error' do
        result = handler.call(context)

        expect(result).to be_error
        expect(result.error_type).to eq(TaskerCore::Types::ErrorTypes::EXTERNAL_SERVICE_ERROR)
      end
    end
  end
end
```

### 4. ActiveSupport::Notifications Bridge

The event bridge republishes Tasker domain events to ActiveSupport::Notifications:

```ruby
# lib/tasker_contrib_rails/event_bridge/active_support_adapter.rb
module TaskerContribRails
  module EventBridge
    class ActiveSupportAdapter < TaskerCore::DomainEvents::BaseSubscriber
      # Subscribe to all domain events
      SUBSCRIBED_EVENTS = [
        'step.execution.started',
        'step.execution.completed',
        'step.execution.failed',
        'task.execution.started',
        'task.execution.completed',
        'task.execution.failed'
      ].freeze

      class << self
        def install!
          SUBSCRIBED_EVENTS.each do |event_name|
            TaskerCore::DomainEvents::SubscriberRegistry.instance.register(
              event_name,
              new
            )
          end
        end
      end

      def handle(event)
        # Translate event name to Rails convention
        notification_name = "tasker.#{event.event_type.tr('.', '_')}"

        # Instrument via ActiveSupport::Notifications
        ActiveSupport::Notifications.instrument(notification_name, {
          event_type: event.event_type,
          task_uuid: event.task_uuid,
          step_uuid: event.step_uuid,
          payload: event.payload,
          timestamp: event.timestamp
        })
      end
    end
  end
end
```

**Usage in Application:**

```ruby
# config/initializers/tasker_subscribers.rb
ActiveSupport::Notifications.subscribe(/^tasker\./) do |name, start, finish, id, payload|
  Rails.logger.info "[Tasker] #{name}: #{payload[:task_uuid]}"
  
  # Send to your observability stack
  StatsD.increment("tasker.#{name}")
end

# Or subscribe to specific events
ActiveSupport::Notifications.subscribe('tasker.step_execution_completed') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  # Handle completion
end
```

### 5. RSpec Helpers

```ruby
# lib/tasker_contrib_rails/testing/rspec_helpers.rb
module TaskerContribRails
  module Testing
    module RSpecHelpers
      # Build a mock StepContext for testing
      def build_step_context(task_fields: {}, dependency_results: {}, step_inputs: {})
        TaskerCore::Types::StepContext.new(
          task_uuid: SecureRandom.uuid,
          step_uuid: SecureRandom.uuid,
          task_name: 'test_task',
          step_name: 'test_step',
          task_context: task_fields,
          workflow_step: build_workflow_step(step_inputs),
          dependency_results: dependency_results
        )
      end

      def build_workflow_step(inputs = {})
        OpenStruct.new(
          workflow_step_uuid: SecureRandom.uuid,
          name: 'test_step',
          inputs: inputs
        )
      end

      # Matchers
      RSpec::Matchers.define :be_success do
        match do |result|
          result.is_a?(TaskerCore::Types::StepHandlerCallResult) &&
            result.success? &&
            result.error_type.nil?
        end
      end

      RSpec::Matchers.define :be_error do
        match do |result|
          result.is_a?(TaskerCore::Types::StepHandlerCallResult) &&
            !result.success? &&
            result.error_type.present?
        end
      end

      RSpec::Matchers.define :have_result_data do |expected|
        match do |result|
          expected.all? { |k, v| result.result_data[k] == v }
        end
      end
    end
  end
end
```

---

## Configuration Strategy

### TOML Files (Primary)

Tasker Core uses TOML configuration. The install generator creates sensible defaults:

```toml
# config/tasker/base/common.toml
[database]
# Uses DATABASE_URL or Rails database.yml by default
# url = "${DATABASE_URL}"

[database.pool]
max_connections = 10
min_connections = 2
connection_timeout_seconds = 30
```

```toml
# config/tasker/base/worker.toml
[web]
enabled = false  # Headless mode for Rails embedding

[handler]
discovery_mode = "template"
template_paths = ["config/tasker/templates"]

[polling]
interval_ms = 10
```

### Rails Configuration (Runtime Overrides)

The initializer allows runtime overrides:

```ruby
# config/initializers/tasker.rb
TaskerCore.configure do |config|
  # Override database URL from credentials
  config.database_url = Rails.application.credentials.tasker_database_url

  # Environment-specific settings
  if Rails.env.production?
    config.pool_max_connections = 30
  end
end
```

### Environment Variables

Key environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `TASKER_WORKER_ENABLED` | Enable worker in this process | `false` |
| `TASKER_ENV` | Configuration environment | `Rails.env` |
| `TASKER_CONFIG_PATH` | Path to merged config | Auto-detected |
| `DATABASE_URL` | Database connection string | Rails default |

---

## Deployment Patterns

### Pattern A: Separate Worker Process

```ruby
# Procfile
web: bundle exec puma -C config/puma.rb
worker: TASKER_WORKER_ENABLED=true bundle exec rails runner 'sleep'
```

### Pattern B: GoodJob Background Job

```ruby
# app/jobs/tasker_worker_job.rb
class TaskerWorkerJob < ApplicationJob
  queue_as :tasker

  def perform
    # Long-running job that starts the worker
    # GoodJob handles process lifecycle
    loop do
      sleep 1
      break if GoodJob.shutdown?
    end
  end
end
```

### Pattern C: Embedded in Puma Worker

```ruby
# config/puma.rb
on_worker_boot do
  if ENV['TASKER_EMBEDDED'] == 'true'
    TaskerCore::Worker::Bootstrap.start!
  end
end

on_worker_shutdown do
  TaskerCore::Worker::Bootstrap.shutdown!
end
```

---

## Testing Strategy

### Unit Tests

```bash
cd rails/tasker-contrib-rails
bundle exec rspec spec/
```

### Integration Tests (Dummy App)

```bash
cd rails/tasker-contrib-rails/spec/dummy
bundle exec rails db:setup
bundle exec rspec spec/integration/
```

### CI Matrix

Test against:
- Ruby 3.2, 3.3
- Rails 7.0, 7.1, 7.2
- PostgreSQL 15, 16

---

## Documentation Deliverables

1. **README.md** - Quick start, installation, basic usage
2. **CHANGELOG.md** - Version history
3. **docs/configuration.md** - Full configuration reference
4. **docs/generators.md** - Generator usage and options
5. **docs/event-bridge.md** - ActiveSupport::Notifications integration
6. **docs/deployment.md** - Production deployment patterns
7. **docs/testing.md** - Testing handlers and workflows

---

## Acceptance Criteria

### Phase 1 Complete When:

- [ ] `gem 'tasker-contrib-rails'` installable from path
- [ ] `rails g tasker:install` creates config structure
- [ ] `rails g tasker:step_handler Foo` creates handler + spec
- [ ] Railtie bootstraps tasker-core-rb on Rails init
- [ ] AS::Notifications bridge publishes events
- [ ] README documents basic usage
- [ ] CI passes on Ruby 3.2+ / Rails 7.0+

### Phase 2 Complete When:

- [ ] Task template generator works
- [ ] Decision handler generator works
- [ ] Batchable handler generator works
- [ ] Generators optionally call `tasker-cli`

### Phase 3 Complete When:

- [ ] RSpec helpers/matchers documented and tested
- [ ] Integration tests pass against dummy app
- [ ] Published to RubyGems (0.1.0)

---

## Open Questions

### 1. ActiveJob Adapter Scope

Should `tasker-contrib-rails` include an ActiveJob adapter, or should that be a separate gem (`tasker-activejob`)?

**Considerations:**
- Pro: Single gem for Rails developers
- Con: Not all Rails apps use ActiveJob
- Con: Adds complexity to initial release

**Current Decision:** Defer to Phase 4. Start with explicit `TaskerCore::Client` usage.

### 2. Engine vs Railtie

Should we provide a full Rails Engine with routes, or just a Railtie?

**Considerations:**
- Tasker Core already has API endpoints via Axum
- Rails devs might want `/tasker/health` routes
- Engine adds complexity and potential conflicts

**Current Decision:** Start with Railtie only. Consider Engine with opt-in routes in Phase 4.

### 3. Handler Registration Strategy

How should handlers be discovered and registered?

**Options:**
- A) Zeitwerk autoload + ObjectSpace scan (like legacy engine)
- B) Explicit registration in initializer
- C) YAML template references (current tasker-core approach)

**Current Decision:** Support both B and C. Explicit registration for simple cases, YAML templates for complex workflows.

---

## Related Documents

- [Foundations](./foundations.md) - Overall tasker-contrib vision
- [CLI Plugin Architecture](./cli-plugin-architecture.md) - How generators integrate with tasker-cli
- [Legacy tasker-engine](https://github.com/tasker-systems/tasker-engine) - Reference implementation
- [tasker-core-rb Documentation](https://github.com/tasker-systems/tasker-core/docs/workers/ruby.md)
