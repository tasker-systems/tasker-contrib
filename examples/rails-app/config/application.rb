require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'rails/test_unit/railtie'

# Load environment variables from .env before anything else
Dotenv::Railtie.load if defined?(Dotenv)

module TaskerExampleRails
  class Application < Rails::Application
    config.load_defaults 7.1
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
