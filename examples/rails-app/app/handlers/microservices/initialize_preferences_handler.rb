module Microservices
  module StepHandlers
    class InitializePreferencesHandler < TaskerCore::StepHandler::Base
      PLAN_DEFAULTS = {
        'free' => {
          theme: 'light',
          notifications: { email: true, push: false, sms: false, slack: false },
          dashboard_layout: 'basic',
          data_retention_days: 30,
          api_rate_limit: 100,
          max_projects: 3,
          max_team_members: 1,
          export_formats: %w[csv]
        },
        'pro' => {
          theme: 'system',
          notifications: { email: true, push: true, sms: false, slack: true },
          dashboard_layout: 'advanced',
          data_retention_days: 365,
          api_rate_limit: 5000,
          max_projects: 25,
          max_team_members: 10,
          export_formats: %w[csv json xlsx pdf]
        },
        'enterprise' => {
          theme: 'system',
          notifications: { email: true, push: true, sms: true, slack: true },
          dashboard_layout: 'custom',
          data_retention_days: 0, # unlimited
          api_rate_limit: 50_000,
          max_projects: 0, # unlimited
          max_team_members: 0, # unlimited
          export_formats: %w[csv json xlsx pdf xml]
        }
      }.freeze

      def call(context)
        account_data = context.get_dependency_field('create_user_account', ['result'])
        marketing_consent = context.get_input('marketing_consent')

        raise TaskerCore::Errors::PermanentError.new(
          'User account data not available',
          error_code: 'MISSING_ACCOUNT'
        ) if account_data.nil?

        user_id = account_data['user_id']
        plan = account_data['plan']

        defaults = PLAN_DEFAULTS[plan]
        raise TaskerCore::Errors::PermanentError.new(
          "No defaults for plan: #{plan}",
          error_code: 'UNKNOWN_PLAN'
        ) if defaults.nil?

        preferences_id = "pref_#{SecureRandom.hex(10)}"
        timezone = 'UTC'
        locale = 'en-US'

        preferences = defaults.merge(
          timezone: timezone,
          locale: locale,
          marketing_consent: marketing_consent == true,
          onboarding_completed: false,
          two_factor_enabled: plan == 'enterprise',
          session_timeout_minutes: plan == 'enterprise' ? 30 : 60
        )

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            preferences_id: preferences_id,
            user_id: user_id,
            plan: plan,
            preferences: preferences,
            feature_flags: {
              beta_features: plan != 'free',
              advanced_analytics: %w[pro enterprise].include?(plan),
              custom_branding: plan == 'enterprise',
              sso_enabled: plan == 'enterprise',
              audit_logging: plan == 'enterprise'
            },
            quotas: {
              max_projects: defaults[:max_projects],
              max_team_members: defaults[:max_team_members],
              api_rate_limit: defaults[:api_rate_limit],
              data_retention_days: defaults[:data_retention_days]
            },
            initialized_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            preferences_id: preferences_id,
            plan: plan,
            feature_count: preferences.keys.size
          }
        )
      end
    end
  end
end
