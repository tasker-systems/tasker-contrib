# frozen_string_literal: true

module Payments
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    ProcessGatewayRefundHandler = step_handler(
      'Payments::StepHandlers::ProcessGatewayRefundHandler',
      depends_on: { eligibility: ['validate_payment_eligibility', Types::Payments::ValidateEligibilityResult] },
      inputs: Types::Payments::ValidateEligibilityInput
    ) do |eligibility:, inputs:, context:|
      Payments::Service.process_gateway(
        eligibility: eligibility,
        refund_reason: inputs.resolved_refund_reason || 'customer_request',
        partial_refund: inputs.partial_refund
      )
    end
  end
end
