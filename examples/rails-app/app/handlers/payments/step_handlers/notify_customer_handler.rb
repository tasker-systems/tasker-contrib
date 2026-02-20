# frozen_string_literal: true

module Payments
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    NotifyCustomerHandler = step_handler(
      'Payments::StepHandlers::NotifyCustomerHandler',
      depends_on: {
        eligibility: ['validate_payment_eligibility', Types::Payments::ValidateEligibilityResult],
        gateway_result: ['process_gateway_refund', Types::Payments::ProcessGatewayResult],
        records_result: ['update_payment_records', Types::Payments::UpdateRecordsResult]
      },
      inputs: Types::Payments::ValidateEligibilityInput
    ) do |eligibility:, gateway_result:, records_result:, inputs:, context:|
      Payments::Service.notify_customer(
        eligibility: eligibility,
        gateway_result: gateway_result,
        records_result: records_result,
        customer_email: inputs.customer_email,
        refund_reason: inputs.refund_reason || 'customer_request'
      )
    end
  end
end
