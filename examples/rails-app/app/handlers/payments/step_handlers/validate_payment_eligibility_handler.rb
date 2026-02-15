module Payments
  module StepHandlers
    class ValidatePaymentEligibilityHandler < TaskerCore::StepHandler::Base
      SUPPORTED_CURRENCIES = %w[USD EUR GBP CAD AUD].freeze
      MAX_REFUND_AMOUNT = {
        'USD' => 50_000.00,
        'EUR' => 45_000.00,
        'GBP' => 40_000.00,
        'CAD' => 65_000.00,
        'AUD' => 75_000.00
      }.freeze
      REFUND_ELIGIBILITY_DAYS = 180

      def call(context)
        payment_id = context.get_input('payment_id')
        refund_amount = context.get_input('refund_amount')
        currency = context.get_input('currency') || 'USD'
        # TAS-137: Source uses 'refund_reason' not 'reason'
        reason = context.get_input('refund_reason') || context.get_input('reason')
        idempotency_key = context.get_input('idempotency_key')
        # TAS-137: Source reads partial_refund with default
        partial_refund = context.get_input_or('partial_refund', false)

        raise TaskerCore::Errors::PermanentError.new(
          'Payment ID is required',
          error_code: 'MISSING_PAYMENT_ID'
        ) if payment_id.blank?

        amount = refund_amount.to_f
        raise TaskerCore::Errors::PermanentError.new(
          "Invalid refund amount: #{amount}",
          error_code: 'INVALID_AMOUNT'
        ) if amount <= 0

        unless SUPPORTED_CURRENCIES.include?(currency)
          raise TaskerCore::Errors::PermanentError.new(
            "Unsupported currency: #{currency}. Supported: #{SUPPORTED_CURRENCIES.join(', ')}",
            error_code: 'UNSUPPORTED_CURRENCY'
          )
        end

        max_amount = MAX_REFUND_AMOUNT[currency]
        if amount > max_amount
          raise TaskerCore::Errors::PermanentError.new(
            "Refund amount #{amount} #{currency} exceeds maximum of #{max_amount} #{currency}",
            error_code: 'EXCEEDS_MAX_AMOUNT'
          )
        end

        # Simulate original payment lookup
        original_amount = (amount + rand(0.0..200.0)).round(2)
        payment_date = Date.current - rand(1..365)
        days_since_payment = (Date.current - payment_date).to_i
        gateway = %w[stripe braintree adyen].sample

        # Check refund window
        within_window = days_since_payment <= REFUND_ELIGIBILITY_DAYS

        # Check for duplicate refund (idempotency)
        idempotency_key ||= "idem_#{SecureRandom.hex(16)}"
        is_duplicate = false # In real system, would check against stored keys

        # Simulate previous refunds on this payment
        previous_refund_total = (rand(0.0..[original_amount * 0.3, 0].max)).round(2)
        remaining_refundable = (original_amount - previous_refund_total).round(2)

        if amount > remaining_refundable
          raise TaskerCore::Errors::PermanentError.new(
            "Refund amount #{amount} exceeds remaining refundable balance of #{remaining_refundable} #{currency}",
            error_code: 'EXCEEDS_REFUNDABLE_BALANCE'
          )
        end

        eligibility_id = "elig_#{SecureRandom.hex(8)}"

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            payment_validated: true,
            payment_id: payment_id,
            original_amount: original_amount,
            refund_amount: amount,
            payment_method: 'credit_card',
            gateway_provider: gateway,
            eligibility_status: (within_window && !is_duplicate) ? 'eligible' : 'ineligible',
            validation_timestamp: Time.current.iso8601,
            namespace: 'payments_rb',
            eligibility_id: eligibility_id,
            eligible: within_window && !is_duplicate,
            currency: currency,
            reason: reason,
            original_payment: {
              amount: original_amount,
              date: payment_date.iso8601,
              gateway: gateway,
              status: 'captured',
              days_since_payment: days_since_payment
            },
            refund_history: {
              previous_refund_total: previous_refund_total,
              remaining_refundable: remaining_refundable,
              refund_count: previous_refund_total > 0 ? rand(1..3) : 0
            },
            idempotency_key: idempotency_key,
            is_duplicate: is_duplicate,
            within_refund_window: within_window,
            validated_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            eligibility_id: eligibility_id,
            eligible: within_window,
            amount: amount,
            currency: currency,
            gateway: gateway,
            eligibility_status: (within_window && !is_duplicate) ? 'eligible' : 'ineligible'
          }
        )
      end
    end
  end
end
