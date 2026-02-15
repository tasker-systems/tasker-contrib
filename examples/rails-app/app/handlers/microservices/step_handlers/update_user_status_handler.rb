module Microservices
  module StepHandlers
    class UpdateUserStatusHandler < TaskerCore::StepHandler::Base
      def call(context)
        # TAS-137: Use get_dependency_result() for upstream step data
        account_data_full = context.get_dependency_result('create_user_account')
        billing_data_full = context.get_dependency_result('setup_billing_profile')
        preferences_data_full = context.get_dependency_result('initialize_preferences')
        welcome_data_full = context.get_dependency_result('send_welcome_sequence')

        account_data = account_data_full&.is_a?(Hash) ? account_data_full : nil
        billing_data = billing_data_full&.is_a?(Hash) ? billing_data_full : nil
        preferences_data = preferences_data_full&.is_a?(Hash) ? preferences_data_full : nil
        welcome_data = welcome_data_full&.is_a?(Hash) ? welcome_data_full : nil

        # TAS-137: Use get_dependency_field() for nested field extraction
        user_id_field = context.get_dependency_field('create_user_account', 'user_id')
        plan_field = context.get_dependency_field('create_user_account', 'plan') || 'free'

        raise TaskerCore::Errors::PermanentError.new(
          'Upstream data not available for status update',
          error_code: 'MISSING_DEPENDENCIES'
        ) if account_data.nil? || billing_data.nil? || preferences_data.nil? || welcome_data.nil?

        user_id = account_data['user_id']
        plan = account_data['plan']
        activated_at = Time.current

        # Compile registration summary
        registration_steps = {
          account_created: true,
          billing_configured: billing_data['billing_id'].present?,
          preferences_initialized: preferences_data['preferences_id'].present?,
          welcome_sequence_sent: welcome_data['all_delivered'],
          notifications_sent: welcome_data['total_notifications'].to_i
        }

        all_steps_completed = registration_steps.values.all? { |v| v == true || (v.is_a?(Integer) && v > 0) }

        # Build user profile summary
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

        # Calculate onboarding score
        onboarding_score = 0
        onboarding_score += 25 if registration_steps[:account_created]
        onboarding_score += 25 if registration_steps[:billing_configured]
        onboarding_score += 25 if registration_steps[:preferences_initialized]
        onboarding_score += 25 if registration_steps[:welcome_sequence_sent]

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
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
            activated_at: activated_at.iso8601,
            registration_duration_seconds: (activated_at - Time.parse(account_data['created_at'])).round(2)
          },
          metadata: {
            handler: self.class.name,
            user_id: user_id,
            status: all_steps_completed ? 'active' : 'partially_active',
            onboarding_score: onboarding_score,
            plan: plan
          }
        )
      end
    end
  end
end
