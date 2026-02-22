# frozen_string_literal: true

module Payments
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    ValidatePaymentEligibilityHandler = step_handler(
      'Payments::StepHandlers::ValidatePaymentEligibilityHandler',
      inputs: Types::Payments::ValidateEligibilityInput
    ) do |inputs:, context:|
      # Input validation (required fields) is handled by the model's validate!
      # method — see Types::Payments::ValidateEligibilityInput in types.rb.
      Payments::Service.validate_eligibility(input: inputs)
    end
  end
end
