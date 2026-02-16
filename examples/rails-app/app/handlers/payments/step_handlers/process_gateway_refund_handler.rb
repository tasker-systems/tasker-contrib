module Payments
  module StepHandlers
    class ProcessGatewayRefundHandler < TaskerCore::StepHandler::Base
      def call(context)
        # TAS-137: Use get_dependency_result() for upstream step results (auto-unwraps)
        eligibility = context.get_dependency_result('validate_payment_eligibility')
        eligibility = eligibility&.is_a?(Hash) ? eligibility : nil

        # TAS-137: Use get_dependency_field() for nested field extraction
        payment_id = context.get_dependency_field('validate_payment_eligibility', 'payment_id')
        refund_amount_dep = context.get_dependency_field('validate_payment_eligibility', 'refund_amount')
        original_amount = context.get_dependency_field('validate_payment_eligibility', 'original_amount')

        # TAS-137: Use get_input_or() for task context with defaults
        refund_reason = context.get_input_or('refund_reason', 'customer_request')
        partial_refund = context.get_input_or('partial_refund', false)

        raise TaskerCore::Errors::PermanentError.new(
          'Eligibility data not available',
          error_code: 'MISSING_ELIGIBILITY'
        ) if eligibility.nil?

        unless eligibility['eligible'] || eligibility['payment_validated']
          raise TaskerCore::Errors::PermanentError.new(
            'Payment is not eligible for refund',
            error_code: 'NOT_ELIGIBLE'
          )
        end

        amount = (refund_amount_dep || eligibility['refund_amount']).to_f
        currency = eligibility['currency']
        gateway = eligibility.dig('original_payment', 'gateway') || eligibility['gateway_provider'] || 'unknown'
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

        refund_id = "rfnd_#{SecureRandom.hex(8)}"

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            refund_processed: true,
            refund_id: refund_id,
            payment_id: payment_id,
            refund_amount: amount,
            refund_status: 'processed',
            gateway_transaction_id: gateway_transaction_id,
            gateway_provider: gateway,
            processed_at: processing_completed_at.iso8601,
            estimated_arrival: estimated_settlement.iso8601,
            namespace: 'payments_rb',
            gateway_request_id: gateway_request_id,
            gateway: gateway,
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
            }
          },
          metadata: {
            handler: self.class.name,
            refund_id: refund_id,
            gateway: gateway,
            gateway_provider: gateway,
            gateway_transaction_id: gateway_transaction_id,
            amount: amount,
            processing_time_ms: processing_time_ms,
            estimated_settlement_days: settlement_days,
            refund_status: 'processed'
          }
        )
      end
    end
  end
end
