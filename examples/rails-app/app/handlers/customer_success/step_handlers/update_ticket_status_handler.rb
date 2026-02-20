# frozen_string_literal: true

module CustomerSuccess
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    UpdateTicketStatusHandler = step_handler(
      'CustomerSuccess::StepHandlers::UpdateTicketStatusHandler',
      depends_on: {
        validation: ['validate_refund_request', Types::CustomerSuccess::ValidateRefundResult],
        policy_check: ['check_refund_policy', Types::CustomerSuccess::CheckPolicyResult],
        approval: ['get_manager_approval', Types::CustomerSuccess::ApproveRefundResult],
        execution: ['execute_refund_workflow', Types::CustomerSuccess::ExecuteRefundResult]
      },
      inputs: Types::CustomerSuccess::ValidateRefundRequestInput
    ) do |validation:, policy_check:, approval:, execution:, inputs:, context:|
      CustomerSuccess::Service.update_ticket_status(
        validation: validation,
        policy_check: policy_check,
        approval: approval,
        execution: execution
      )
    end
  end
end
