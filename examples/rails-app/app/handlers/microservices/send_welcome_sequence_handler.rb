module Microservices
  module StepHandlers
    class SendWelcomeSequenceHandler < TaskerCore::StepHandler::Base
      def call(context)
        account_data = context.get_dependency_field('create_user_account', ['result'])
        billing_data = context.get_dependency_field('setup_billing_profile', ['result'])
        preferences_data = context.get_dependency_field('initialize_preferences', ['result'])

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

        # Email welcome message (always sent)
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

        # Trial notification if applicable
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

        # Push notification
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

        # Slack notification
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

        # In-app notification (always)
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

        # Schedule drip campaign
        drip_schedule = [
          { day: 1, template: 'getting_started', subject: 'Getting started with Tasker' },
          { day: 3, template: 'first_workflow',  subject: 'Create your first workflow' },
          { day: 7, template: 'tips_tricks',     subject: '5 tips to boost productivity' }
        ]

        if has_trial
          drip_schedule << { day: 10, template: 'trial_reminder', subject: "Your trial ends in #{billing_data['trial_days'].to_i - 10} days" }
        end

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            sequence_id: "seq_#{SecureRandom.hex(8)}",
            user_id: user_id,
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
          },
          metadata: {
            handler: self.class.name,
            user_id: user_id,
            channels_used: notifications_sent.map { |n| n[:channel] }.uniq,
            notifications_sent: notifications_sent.size,
            drip_emails_scheduled: drip_schedule.size
          }
        )
      end
    end
  end
end
