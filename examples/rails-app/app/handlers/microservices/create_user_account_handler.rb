module Microservices
  module StepHandlers
    class CreateUserAccountHandler < TaskerCore::StepHandler::Base
      EMAIL_REGEX = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
      BLOCKED_DOMAINS = %w[tempmail.com throwaway.email mailinator.com].freeze

      def call(context)
        email = context.get_input('email')
        name = context.get_input('name')
        plan = context.get_input('plan')
        referral_code = context.get_input('referral_code')

        # Validate email
        raise TaskerCore::Errors::PermanentError.new(
          'Email address is required',
          error_code: 'MISSING_EMAIL'
        ) if email.blank?

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

        # Validate name
        raise TaskerCore::Errors::PermanentError.new(
          'Name is required',
          error_code: 'MISSING_NAME'
        ) if name.blank?

        # Validate plan
        valid_plans = %w[free pro enterprise]
        raise TaskerCore::Errors::PermanentError.new(
          "Invalid plan: #{plan}. Must be one of: #{valid_plans.join(', ')}",
          error_code: 'INVALID_PLAN'
        ) unless valid_plans.include?(plan)

        # Generate user account
        user_id = "usr_#{SecureRandom.hex(12)}"
        username = "#{name.downcase.gsub(/[^a-z0-9]/, '_')}_#{SecureRandom.hex(3)}"
        created_at = Time.current

        # Validate referral code if present
        referral_valid = referral_code.present? && referral_code.match?(/\AREF-[A-Z0-9]{8}\z/)

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            user_id: user_id,
            username: username,
            email: email.downcase,
            name: name,
            plan: plan,
            referral_code: referral_code,
            referral_valid: referral_valid,
            account_status: 'created',
            email_verified: false,
            verification_token: SecureRandom.urlsafe_base64(32),
            created_at: created_at.iso8601
          },
          metadata: {
            handler: self.class.name,
            user_id: user_id,
            plan: plan,
            referral_valid: referral_valid
          }
        )
      end
    end
  end
end
