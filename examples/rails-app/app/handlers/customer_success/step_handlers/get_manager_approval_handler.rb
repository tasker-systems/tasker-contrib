# frozen_string_literal: true

module CustomerSuccess
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    GetManagerApprovalHandler = step_handler(
      'CustomerSuccess::StepHandlers::GetManagerApprovalHandler',
      depends_on: {
        policy_check: ['check_refund_policy', Types::CustomerSuccess::CheckPolicyResult],
        validation: ['validate_refund_request', Types::CustomerSuccess::ValidateRefundResult]
      },
      inputs: Types::CustomerSuccess::ValidateRefundRequestInput
    ) do |policy_check:, validation:, inputs:, context:|
      CustomerSuccess::Service.get_manager_approval(
        validation: validation,
        policy_check: policy_check
      )
    end
  end
end
