module Payments
  module StepHandlers
    class ProcessGatewayRefundHandler < TaskerCore::StepHandler::Base
      def call(context)
        eligibility = context.get_dependency_field('validate_payment_eligibility', ['result'])

        raise TaskerCore::Errors::PermanentError.new(
          'Eligibility data not available',
          error_code: 'MISSING_ELIGIBILITY'
        ) if eligibility.nil?

        unless eligibility['eligible']
          raise TaskerCore::Errors::PermanentError.new(
            'Payment is not eligible for refund',
            error_code: 'NOT_ELIGIBLE'
          )
        end

        amount = eligibility['refund_amount'].to_f
        currency = eligibility['currency']
        payment_id = eligibility['payment_id']
        gateway = eligibility.dig('original_payment', 'gateway') || 'unknown'
        idempotency_key = eligibility['idempotency_key']

        # Simulate gateway-specific processing
        gateway_request_id = "gw_req_#{SecureRandom.hex(12)}"
        processing_started_at = Time.current

        # Simulate potential gateway issues
        if gateway == 'unknown'
          raise TaskerCore::Errors::RetryableError.new(
            'Unable to determine payment gateway - retrying'
          )
        end

        # Simulate gateway response
        gateway_transaction_id = case gateway
                                 when 'stripe'    then "re_#{SecureRandom.hex(12)}"
                                 when 'braintree' then "bt_rfnd_#{SecureRandom.hex(8)}"
                                 when 'adyen'     then "ADY-#{SecureRandom.hex(10).upcase}"
                                 end

        processing_time_ms = rand(200..3000)
        processing_completed_at = processing_started_at + (processing_time_ms / 1000.0)

        # Determine settlement timeline based on gateway
        settlement_days = case gateway
                          when 'stripe'    then rand(5..10)
                          when 'braintree' then rand(3..7)
                          when 'adyen'     then rand(5..14)
                          end

        estimated_settlement = (Date.current + settlement_days)

        # Calculate any gateway fees
        gateway_fee_rate = case gateway
                           when 'stripe'    then 0.0025
                           when 'braintree' then 0.0020
                           when 'adyen'     then 0.0030
                           end
        gateway_fee = (amount * gateway_fee_rate).round(2)
        net_refund = (amount - gateway_fee).round(2)

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            gateway_request_id: gateway_request_id,
            gateway_transaction_id: gateway_transaction_id,
            gateway: gateway,
            payment_id: payment_id,
            refund_amount: amount,
            gateway_fee: gateway_fee,
            net_refund_amount: net_refund,
            currency: currency,
            status: 'processed',
            idempotency_key: idempotency_key,
            processing_time_ms: processing_time_ms,
            settlement: {
              estimated_days: settlement_days,
              estimated_date: estimated_settlement.iso8601,
              method: eligibility.dig('original_payment', 'status') == 'captured' ? 'original_method' : 'account_credit'
            },
            gateway_response: {
              code: '200',
              message: 'Refund processed successfully',
              raw_response_id: "resp_#{SecureRandom.hex(8)}"
            },
            processed_at: processing_completed_at.iso8601
          },
          metadata: {
            handler: self.class.name,
            gateway: gateway,
            gateway_transaction_id: gateway_transaction_id,
            amount: amount,
            processing_time_ms: processing_time_ms,
            estimated_settlement_days: settlement_days
          }
        )
      end
    end
  end
end
