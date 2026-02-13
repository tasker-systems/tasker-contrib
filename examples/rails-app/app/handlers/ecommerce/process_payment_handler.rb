module Ecommerce
  module StepHandlers
    class ProcessPaymentHandler < TaskerCore::StepHandler::Base
      DECLINED_TOKENS = %w[tok_test_declined tok_insufficient_funds tok_expired].freeze
      GATEWAY_ERROR_TOKENS = %w[tok_gateway_error tok_timeout].freeze

      def call(context)
        payment_token = context.get_input('payment_token')
        customer_email = context.get_input('customer_email')
        cart_validation = context.get_dependency_field('validate_cart', ['result'])

        raise TaskerCore::Errors::PermanentError.new(
          'Payment token is required',
          error_code: 'MISSING_TOKEN'
        ) if payment_token.blank?

        raise TaskerCore::Errors::PermanentError.new(
          'Cart validation data not available',
          error_code: 'MISSING_CART_VALIDATION'
        ) if cart_validation.nil?

        total = cart_validation['total'].to_f

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
        transaction_id = "txn_#{SecureRandom.hex(12)}"
        authorization_code = "auth_#{SecureRandom.hex(6).upcase}"
        processed_at = Time.current

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            transaction_id: transaction_id,
            authorization_code: authorization_code,
            amount_charged: total,
            currency: 'USD',
            payment_method: 'card',
            last_four: payment_token.gsub(/[^0-9]/, '').last(4).rjust(4, '0'),
            customer_email: customer_email,
            status: 'captured',
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
