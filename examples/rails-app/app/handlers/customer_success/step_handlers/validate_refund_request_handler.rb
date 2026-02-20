# frozen_string_literal: true

module CustomerSuccess
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    ValidateRefundRequestHandler = step_handler(
      'CustomerSuccess::StepHandlers::ValidateRefundRequestHandler',
      inputs: Types::CustomerSuccess::ValidateRefundRequestInput
    ) do |inputs:, context:|
      # Input validation (required fields) is handled by the model's validate!
      # method — see Types::CustomerSuccess::ValidateRefundRequestInput in types.rb.
      CustomerSuccess::Service.validate_refund_request(input: inputs)
    end
  end
end
