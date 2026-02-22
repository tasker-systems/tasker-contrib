# frozen_string_literal: true

require 'tasker_core'

# Bootstrap the Tasker worker FFI bridge.
# This connects this Rails app to the Tasker orchestration service,
# enabling it to receive and process workflow steps.
TaskerCore::Worker::Bootstrap.start!
