# frozen_string_literal: true

module CustomerSuccess
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    ExecuteRefundWorkflowHandler = step_handler(
      'CustomerSuccess::StepHandlers::ExecuteRefundWorkflowHandler',
      depends_on: {
        approval: ['get_manager_approval', Types::CustomerSuccess::ApproveRefundResult],
        validation: ['validate_refund_request', Types::CustomerSuccess::ValidateRefundResult]
      },
      inputs: Types::CustomerSuccess::ValidateRefundRequestInput
    ) do |approval:, validation:, inputs:, context:|
      CustomerSuccess::Service.execute_refund_workflow(
        validation: validation,
        approval: approval,
        correlation_id: inputs.correlation_id || "cs-#{SecureRandom.hex(8)}"
      )
    end
  end
end
