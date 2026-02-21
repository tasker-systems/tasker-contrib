# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'active_job/railtie'
# require 'rails/test_unit/railtie'  # Using RSpec instead

# Load environment variables from .env (dotenv ~> 2.8 via tasker-rb)
require 'dotenv'
Dotenv.load

module TaskerExampleRails
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true

    # Autoload handler paths
    config.autoload_paths << Rails.root.join('app', 'handlers')

    # Timezone
    config.time_zone = 'UTC'

    # Generators
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
      g.test_framework :rspec
    end
  end
end
