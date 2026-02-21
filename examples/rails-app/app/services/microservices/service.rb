# frozen_string_literal: true

# Service functions return Dry::Struct instances from Types::Microservices.
# See Types::Microservices in app/services/types.rb for full struct definitions.
#   create_user_account      -> Types::Microservices::CreateUserResult
#   setup_billing_profile    -> Types::Microservices::SetupBillingResult
#   initialize_preferences   -> Types::Microservices::InitPreferencesResult
#   send_welcome_sequence    -> Types::Microservices::SendWelcomeResult
#   update_user_status       -> Types::Microservices::UpdateStatusResult
module Microservices
  module Service
    EMAIL_REGEX = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
    BLOCKED_DOMAINS = %w[tempmail.com throwaway.email mailinator.com].freeze
    VALID_PLANS = %w[free pro enterprise].freeze

    PLAN_PRICING = {
      'free'       => { monthly: 0.00,    annual: 0.00,     features: %w[basic_access community_support 1gb_storage] },
      'pro'        => { monthly: 29.99,   annual: 299.90,   features: %w[basic_access priority_support 50gb_storage api_access analytics] },
      'enterprise' => { monthly: 299.99,  annual: 2999.90,  features: %w[basic_access dedicated_support unlimited_storage api_access analytics sso audit_logs custom_integrations] }
    }.freeze

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
        data_retention_days: 0,
        api_rate_limit: 50_000,
        max_projects: 0,
        max_team_members: 0,
        export_formats: %w[csv json xlsx pdf xml]
      }
    }.freeze

    module_function

    def create_user_account(input:)
      email = input.email
      name = input.name
      plan = input.plan
      referral_code = input.referral_code

      raise TaskerCore::Errors::PermanentError.new(
        "Invalid email format: #{email}",
        error_code: 'INVALID_EMAIL'
      ) unless email.match?(EMAIL_REGEX)

      email_domain = email.split('@').last&.downcase
      if BLOCKED_DOMAINS.include?(email_domain)
        raise TaskerCore::Errors::PermanentError.new(
          "Disposable email addresses are not allowed: #{email_domain}",
          error_code: 'BLOCKED_EMAIL_DOMAIN'
        )
      end

      plan ||= 'free'
      raise TaskerCore::Errors::PermanentError.new(
        "Invalid plan: #{plan}. Must be one of: #{VALID_PLANS.join(', ')}",
        error_code: 'INVALID_PLAN'
      ) unless VALID_PLANS.include?(plan)

      user_id = "usr_#{SecureRandom.hex(12)}"
      username = "#{name.downcase.gsub(/[^a-z0-9]/, '_')}_#{SecureRandom.hex(3)}"
      created_at = Time.current
      referral_valid = referral_code.present? && referral_code.match?(/\AREF-[A-Z0-9]{8}\z/)

      Types::Microservices::CreateUserResult.new(
        user_id: user_id,
        username: username,
        email: email.downcase,
        name: name,
        plan: plan,
        referral_code: referral_code,
        referral_valid: referral_valid,
        status: 'created',
        account_status: 'created',
        email_verified: false,
        verification_token: SecureRandom.urlsafe_base64(32),
        created_at: created_at.iso8601
      )
    end

    def setup_billing_profile(account_data:)
      raise TaskerCore::Errors::PermanentError.new(
        'User account data not available',
        error_code: 'MISSING_ACCOUNT'
      ) if account_data.nil?

      user_id = account_data['user_id']
      plan = account_data['plan']
      referral_valid = account_data['referral_valid']

      plan_details = PLAN_PRICING[plan]
      raise TaskerCore::Errors::PermanentError.new(
        "Unknown plan: #{plan}",
        error_code: 'UNKNOWN_PLAN'
      ) if plan_details.nil?

      billing_id = "bill_#{SecureRandom.hex(10)}"
      subscription_id = "sub_#{SecureRandom.hex(10)}"

      monthly_price = plan_details[:monthly]
      discount_percent = 0
      if referral_valid && monthly_price > 0
        discount_percent = 20
        monthly_price = (monthly_price * 0.80).round(2)
      end

      trial_days = plan == 'free' ? 0 : 14
      trial_end = trial_days > 0 ? (Time.current + trial_days.days).iso8601 : nil

      Types::Microservices::SetupBillingResult.new(
        billing_id: billing_id,
        subscription_id: subscription_id,
        user_id: user_id,
        plan: plan,
        billing_cycle: 'monthly',
        monthly_price: monthly_price,
        annual_price: plan_details[:annual],
        currency: 'USD',
        features: plan_details[:features],
        trial_days: trial_days,
        trial_end_date: trial_end,
        payment_method_required: plan != 'free',
        next_billing_date: (Time.current + (trial_days > 0 ? trial_days : 30).days).to_date.iso8601,
        price: monthly_price,
        status: plan == 'free' ? 'active' : 'trial',
        billing_status: plan == 'free' ? 'active' : 'trial',
        created_at: Time.current.iso8601
      )
    end

    def initialize_preferences(account_data:, marketing_consent:)
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

      preferences = defaults.merge(
        timezone: 'UTC',
        locale: 'en-US',
        marketing_consent: marketing_consent == true,
        onboarding_completed: false,
        two_factor_enabled: plan == 'enterprise',
        session_timeout_minutes: plan == 'enterprise' ? 30 : 60
      )

      Types::Microservices::InitPreferencesResult.new(
        preferences_id: preferences_id,
        user_id: user_id,
        plan: plan,
        preferences: preferences,
        defaults_applied: defaults.keys.count,
        customizations: 0,
        status: 'active',
        created_at: Time.current.iso8601,
        updated_at: Time.current.iso8601,
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
      )
    end

    def send_welcome_sequence(account_data:, billing_data:, preferences_data:)
      raise TaskerCore::Errors::PermanentError.new(
        'Upstream data not available for welcome sequence',
        error_code: 'MISSING_DEPENDENCIES'
      ) if account_data.nil? || billing_data.nil? || preferences_data.nil?

      user_id = account_data['user_id']
      email = account_data['email']
      name = account_data['name']
      plan = account_data['plan']
      has_trial = billing_data['trial_days'].to_i > 0
      notifications = preferences_data.dig('preferences', 'notifications') || {}

      sent_at = Time.current
      notifications_sent = []

      if notifications['email'] != false
        notifications_sent << {
          channel: 'email',
          type: 'welcome',
          recipient: email,
          message_id: "msg_#{SecureRandom.hex(12)}",
          subject: "Welcome to Tasker, #{name}!",
          template: 'welcome_email',
          status: 'sent',
          sent_at: sent_at.iso8601
        }
      end

      if has_trial
        notifications_sent << {
          channel: 'email',
          type: 'trial_started',
          recipient: email,
          message_id: "msg_#{SecureRandom.hex(12)}",
          subject: "Your #{plan.capitalize} trial has started",
          template: 'trial_started',
          status: 'sent',
          sent_at: sent_at.iso8601
        }
      end

      if notifications['push'] == true
        notifications_sent << {
          channel: 'push',
          type: 'welcome',
          device_token: "device_#{SecureRandom.hex(16)}",
          message_id: "push_#{SecureRandom.hex(8)}",
          title: 'Welcome aboard!',
          body: "Your #{plan} account is ready. Let's get started!",
          status: 'delivered',
          sent_at: sent_at.iso8601
        }
      end

      if notifications['slack'] == true
        notifications_sent << {
          channel: 'slack',
          type: 'welcome',
          webhook_id: "hook_#{SecureRandom.hex(8)}",
          message_id: "slack_#{SecureRandom.hex(8)}",
          channel_name: '#onboarding',
          message: "New user registered: #{name} (#{plan} plan)",
          status: 'delivered',
          sent_at: sent_at.iso8601
        }
      end

      notifications_sent << {
        channel: 'in_app',
        type: 'onboarding',
        notification_id: "notif_#{SecureRandom.hex(8)}",
        title: 'Complete your setup',
        body: 'Follow the onboarding checklist to get the most out of Tasker',
        action_url: '/onboarding',
        status: 'created',
        sent_at: sent_at.iso8601
      }

      drip_schedule = [
        { day: 1, template: 'getting_started', subject: 'Getting started with Tasker' },
        { day: 3, template: 'first_workflow',  subject: 'Create your first workflow' },
        { day: 7, template: 'tips_tricks',     subject: '5 tips to boost productivity' }
      ]

      if has_trial
        drip_schedule << { day: 10, template: 'trial_reminder', subject: "Your trial ends in #{billing_data['trial_days'].to_i - 10} days" }
      end

      channels_used = notifications_sent.map { |n| n[:channel] }.uniq

      Types::Microservices::SendWelcomeResult.new(
        user_id: user_id,
        plan: plan,
        channels_used: channels_used,
        messages_sent: notifications_sent.size,
        welcome_sequence_id: "welcome_#{SecureRandom.hex(6)}",
        status: 'sent',
        sent_at: sent_at.iso8601,
        sequence_id: "seq_#{SecureRandom.hex(8)}",
        email: email,
        notifications_sent: notifications_sent,
        total_notifications: notifications_sent.size,
        all_delivered: notifications_sent.all? { |n| %w[sent delivered created].include?(n[:status]) },
        drip_campaign: {
          campaign_id: "drip_#{SecureRandom.hex(8)}",
          emails_scheduled: drip_schedule.size,
          schedule: drip_schedule
        },
        welcome_sequence_completed_at: sent_at.iso8601
      )
    end

    def update_user_status(account_data:, billing_data:, preferences_data:, welcome_data:)
      raise TaskerCore::Errors::PermanentError.new(
        'Upstream data not available for status update',
        error_code: 'MISSING_DEPENDENCIES'
      ) if account_data.nil? || billing_data.nil? || preferences_data.nil? || welcome_data.nil?

      user_id = account_data['user_id']
      plan = account_data['plan']
      activated_at = Time.current

      registration_steps = {
        account_created: true,
        billing_configured: billing_data['billing_id'].present?,
        preferences_initialized: preferences_data['preferences_id'].present?,
        welcome_sequence_sent: welcome_data['all_delivered'],
        notifications_sent: welcome_data['total_notifications'].to_i
      }

      all_steps_completed = registration_steps.values.all? { |v| v == true || (v.is_a?(Integer) && v > 0) }

      profile_summary = {
        user_id: user_id,
        username: account_data['username'],
        email: account_data['email'],
        name: account_data['name'],
        plan: plan,
        billing_id: billing_data['billing_id'],
        subscription_id: billing_data['subscription_id'],
        preferences_id: preferences_data['preferences_id'],
        monthly_price: billing_data['monthly_price'],
        trial_end_date: billing_data['trial_end_date'],
        features: billing_data['features'],
        quotas: preferences_data['quotas']
      }

      onboarding_score = 0
      onboarding_score += 25 if registration_steps[:account_created]
      onboarding_score += 25 if registration_steps[:billing_configured]
      onboarding_score += 25 if registration_steps[:preferences_initialized]
      onboarding_score += 25 if registration_steps[:welcome_sequence_sent]

      Types::Microservices::UpdateStatusResult.new(
        user_id: user_id,
        status: all_steps_completed ? 'active' : 'partially_active',
        plan: plan,
        registration_summary: profile_summary,
        activation_timestamp: activated_at.iso8601,
        all_services_coordinated: all_steps_completed,
        services_completed: %w[
          user_service
          billing_service
          preferences_service
          notification_service
        ],
        registration_complete: all_steps_completed,
        registration_steps: registration_steps,
        onboarding_score: onboarding_score,
        profile_summary: profile_summary,
        next_steps: all_steps_completed ? ['complete_onboarding_checklist', 'create_first_project'] : ['review_incomplete_steps'],
        activated_at: activated_at.iso8601
      )
    end
  end
end
