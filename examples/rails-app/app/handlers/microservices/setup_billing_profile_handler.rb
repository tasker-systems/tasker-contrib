module Microservices
  module StepHandlers
    class SetupBillingProfileHandler < TaskerCore::StepHandler::Base
      PLAN_PRICING = {
        'free'       => { monthly: 0.00,    annual: 0.00,     features: %w[basic_access community_support 1gb_storage] },
        'pro'        => { monthly: 29.99,   annual: 299.90,   features: %w[basic_access priority_support 50gb_storage api_access analytics] },
        'enterprise' => { monthly: 299.99,  annual: 2999.90,  features: %w[basic_access dedicated_support unlimited_storage api_access analytics sso audit_logs custom_integrations] }
      }.freeze

      def call(context)
        account_data = context.get_dependency_field('create_user_account', ['result'])

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

        # Apply referral discount if valid
        monthly_price = plan_details[:monthly]
        discount_percent = 0
        if referral_valid && monthly_price > 0
          discount_percent = 20
          monthly_price = (monthly_price * 0.80).round(2)
        end

        trial_days = plan == 'free' ? 0 : 14
        trial_end = trial_days > 0 ? (Time.current + trial_days.days).iso8601 : nil

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            billing_id: billing_id,
            subscription_id: subscription_id,
            user_id: user_id,
            plan: plan,
            billing_cycle: 'monthly',
            monthly_price: monthly_price,
            annual_price: plan_details[:annual],
            currency: 'USD',
            discount_percent: discount_percent,
            discount_reason: referral_valid ? 'referral' : nil,
            features: plan_details[:features],
            trial_days: trial_days,
            trial_end_date: trial_end,
            payment_method_required: plan != 'free',
            next_billing_date: (Time.current + (trial_days > 0 ? trial_days : 30).days).to_date.iso8601,
            billing_status: plan == 'free' ? 'active' : 'trial',
            created_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            billing_id: billing_id,
            plan: plan,
            monthly_price: monthly_price,
            has_trial: trial_days > 0,
            referral_discount: referral_valid
          }
        )
      end
    end
  end
end
