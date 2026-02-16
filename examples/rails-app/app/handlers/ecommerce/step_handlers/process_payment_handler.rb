module Ecommerce
  module StepHandlers
    class ProcessPaymentHandler < TaskerCore::StepHandler::Base
      DECLINED_TOKENS = %w[tok_test_declined tok_insufficient_funds tok_expired].freeze
      GATEWAY_ERROR_TOKENS = %w[tok_gateway_error tok_timeout].freeze

      def call(context)
        # TAS-137: Use get_input() for task context access (cross-language standard)
        payment_info = context.get_input('payment_info')
        payment_info = payment_info&.deep_symbolize_keys || {}

        # TAS-137: Use get_dependency_field() for nested field extraction
        total = context.get_dependency_field('validate_cart', 'total')

        payment_token = payment_info[:token]
        payment_method = payment_info[:method] || 'card'

        raise TaskerCore::Errors::PermanentError.new(
          'Payment token is required',
          error_code: 'MISSING_TOKEN'
        ) if payment_token.blank?

        raise TaskerCore::Errors::PermanentError.new(
          'Cart total not available from validate_cart step',
          error_code: 'MISSING_CART_TOTAL'
        ) if total.nil?

        total = total.to_f

        raise TaskerCore::Errors::PermanentError.new(
          'Order total must be greater than zero',
          error_code: 'INVALID_TOTAL'
        ) if total <= 0

        # Simulate payment gateway behavior based on token
        if DECLINED_TOKENS.include?(payment_token)
          decline_reason = case payment_token
                           when 'tok_test_declined'       then 'Card declined by issuer'
                           when 'tok_insufficient_funds'   then 'Insufficient funds'
                           when 'tok_expired'              then 'Card expired'
                           end
          raise TaskerCore::Errors::PermanentError.new(
            "Payment declined: #{decline_reason}",
            error_code: 'PAYMENT_DECLINED'
          )
        end

        if GATEWAY_ERROR_TOKENS.include?(payment_token)
          raise TaskerCore::Errors::RetryableError.new(
            "Payment gateway temporarily unavailable for token #{payment_token}"
          )
        end

        # Simulate successful payment
        payment_id = "pay_#{SecureRandom.hex(12)}"
        transaction_id = "txn_#{SecureRandom.hex(12)}"
        authorization_code = "auth_#{SecureRandom.hex(6).upcase}"
        processed_at = Time.current

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            payment_id: payment_id,
            transaction_id: transaction_id,
            authorization_code: authorization_code,
            amount_charged: total,
            currency: 'USD',
            payment_method_type: payment_method,
            last_four: payment_token.gsub(/[^0-9]/, '').last(4).rjust(4, '0'),
            status: 'completed',
            gateway_response_code: '00',
            processed_at: processed_at.iso8601
          },
          metadata: {
            handler: self.class.name,
            transaction_id: transaction_id,
            amount: total,
            gateway: 'simulated'
          }
        )
      end
    end
  end
end
