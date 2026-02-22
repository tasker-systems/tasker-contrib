# frozen_string_literal: true

module CustomerSuccess
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    CheckRefundPolicyHandler = step_handler(
      'CustomerSuccess::StepHandlers::CheckRefundPolicyHandler',
      depends_on: { validation: ['validate_refund_request', Types::CustomerSuccess::ValidateRefundResult] },
      inputs: Types::CustomerSuccess::ValidateRefundRequestInput
    ) do |validation:, inputs:, context:|
      CustomerSuccess::Service.check_refund_policy(
        validation: validation
      )
    end
  end
end
