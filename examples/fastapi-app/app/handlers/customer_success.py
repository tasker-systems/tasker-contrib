"""Customer Success namespace step handlers for refund processing.

5 sequential steps owned by the Customer Success team:
  validate_refund_request -> check_refund_policy -> approve_refund
      -> execute_refund -> update_ticket

Thin DSL wrappers that delegate to app.services.customer_success for business logic.
"""

from __future__ import annotations

from tasker_core.step_handler.functional import depends_on, inputs, step_handler
from tasker_core.types import StepContext

from app.services import customer_success as svc
from app.services.types import (
    CustomerSuccessApproveRefundResult,
    CustomerSuccessCheckPolicyResult,
    CustomerSuccessExecuteRefundResult,
    CustomerSuccessValidateRefundResult,
    ValidateRefundRequestInput,
)


@step_handler("validate_refund_request")
@inputs(ValidateRefundRequestInput)
def validate_refund_request(inputs: ValidateRefundRequestInput, context: StepContext):
    # Input validation (required fields, coercion) is handled by the model's
    # @model_validator — see ValidateRefundRequestInput in app/services/types.py.
    return svc.validate_refund_request(
        ValidateRefundRequestInput(
            ticket_id=inputs.resolved_ticket_id,
            customer_id=inputs.customer_id,
            refund_amount=inputs.resolved_amount,
            refund_reason=inputs.resolved_reason,
            customer_email=inputs.customer_email,
        )
    )


@step_handler("check_refund_policy")
@depends_on(validation=("validate_refund_request", CustomerSuccessValidateRefundResult))
@inputs(ValidateRefundRequestInput)
def check_refund_policy(
    validation: CustomerSuccessValidateRefundResult,
    inputs: ValidateRefundRequestInput,
    context: StepContext,
):
    return svc.check_refund_policy(
        validation=validation,
        refund_amount=inputs.resolved_amount,
    )


@step_handler("get_manager_approval")
@depends_on(
    policy=("check_refund_policy", CustomerSuccessCheckPolicyResult),
    validation=("validate_refund_request", CustomerSuccessValidateRefundResult),
)
@inputs(ValidateRefundRequestInput)
def approve_refund(
    policy: CustomerSuccessCheckPolicyResult,
    validation: CustomerSuccessValidateRefundResult,
    inputs: ValidateRefundRequestInput,
    context: StepContext,
):
    return svc.approve_refund(
        policy=policy,
        validation=validation,
        refund_amount=inputs.resolved_amount,
    )


@step_handler("execute_refund_workflow")
@depends_on(
    approval=("get_manager_approval", CustomerSuccessApproveRefundResult),
    validation=("validate_refund_request", CustomerSuccessValidateRefundResult),
)
@inputs(ValidateRefundRequestInput)
def execute_refund(
    approval: CustomerSuccessApproveRefundResult,
    validation: CustomerSuccessValidateRefundResult,
    inputs: ValidateRefundRequestInput,
    context: StepContext,
):
    return svc.execute_refund(
        approval=approval,
        validation=validation,
        refund_amount=inputs.resolved_amount,
        correlation_id=inputs.correlation_id,
    )


@step_handler("update_ticket_status")
@depends_on(
    delegation_result=("execute_refund_workflow", CustomerSuccessExecuteRefundResult),
    validation=("validate_refund_request", CustomerSuccessValidateRefundResult),
)
@inputs(ValidateRefundRequestInput)
def update_ticket(
    delegation_result: CustomerSuccessExecuteRefundResult,
    validation: CustomerSuccessValidateRefundResult,
    inputs: ValidateRefundRequestInput,
    context: StepContext,
):
    return svc.update_ticket(
        delegation_result=delegation_result,
        validation=validation,
        refund_amount=inputs.resolved_amount,
    )
