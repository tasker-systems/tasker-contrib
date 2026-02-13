module CustomerSuccess
  module StepHandlers
    class ValidateRefundRequestHandler < TaskerCore::StepHandler::Base
      VALID_REASONS = %w[defective not_as_described changed_mind late_delivery duplicate_charge].freeze

      def call(context)
        ticket_id = context.get_input('ticket_id')
        order_ref = context.get_input('order_ref')
        customer_id = context.get_input('customer_id')
        refund_amount = context.get_input('refund_amount')
        reason = context.get_input('reason')

        # Validate required fields
        missing = []
        missing << 'ticket_id' if ticket_id.blank?
        missing << 'order_ref' if order_ref.blank?
        missing << 'customer_id' if customer_id.blank?
        missing << 'refund_amount' if refund_amount.nil?
        missing << 'reason' if reason.blank?

        unless missing.empty?
          raise TaskerCore::Errors::PermanentError.new(
            "Missing required fields: #{missing.join(', ')}",
            error_code: 'MISSING_FIELDS'
          )
        end

        amount = refund_amount.to_f
        raise TaskerCore::Errors::PermanentError.new(
          "Invalid refund amount: #{amount}. Must be greater than 0",
          error_code: 'INVALID_AMOUNT'
        ) if amount <= 0

        raise TaskerCore::Errors::PermanentError.new(
          "Invalid refund amount: #{amount}. Maximum single refund is $10,000",
          error_code: 'AMOUNT_EXCEEDS_LIMIT'
        ) if amount > 10_000

        unless VALID_REASONS.include?(reason)
          raise TaskerCore::Errors::PermanentError.new(
            "Invalid reason: #{reason}. Must be one of: #{VALID_REASONS.join(', ')}",
            error_code: 'INVALID_REASON'
          )
        end

        # Simulate order lookup
        order_data = {
          order_ref: order_ref,
          original_amount: (amount + rand(0.0..50.0)).round(2),
          order_date: (Date.current - rand(1..90)).iso8601,
          items_count: rand(1..5),
          payment_method: %w[credit_card debit_card paypal].sample,
          previous_refunds: rand(0..2),
          customer_tier: %w[standard premium vip].sample
        }

        validation_id = "val_#{SecureRandom.hex(8)}"

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            validation_id: validation_id,
            ticket_id: ticket_id,
            order_ref: order_ref,
            customer_id: customer_id,
            refund_amount: amount,
            reason: reason,
            order_data: order_data,
            refund_percentage: ((amount / order_data[:original_amount]) * 100).round(1),
            is_partial_refund: amount < order_data[:original_amount],
            is_valid: true,
            validated_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            validation_id: validation_id,
            amount: amount,
            reason: reason,
            customer_tier: order_data[:customer_tier]
          }
        )
      end
    end
  end
end
