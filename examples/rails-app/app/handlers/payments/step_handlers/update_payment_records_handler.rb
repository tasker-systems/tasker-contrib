# frozen_string_literal: true

module Payments
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    UpdatePaymentRecordsHandler = step_handler(
      'Payments::StepHandlers::UpdatePaymentRecordsHandler',
      depends_on: {
        eligibility: ['validate_payment_eligibility', Types::Payments::ValidateEligibilityResult],
        gateway_result: ['process_gateway_refund', Types::Payments::ProcessGatewayResult]
      },
      inputs: Types::Payments::ValidateEligibilityInput
    ) do |eligibility:, gateway_result:, inputs:, context:|
      Payments::Service.update_records(
        eligibility: eligibility,
        gateway_result: gateway_result,
        refund_reason: inputs.refund_reason || 'customer_request'
      )
    end
  end
end
