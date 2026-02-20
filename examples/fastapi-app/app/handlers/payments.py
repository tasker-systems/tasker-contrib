"""Payments namespace step handlers for refund processing.

4 sequential steps owned by the Payments team:
  ValidateEligibility -> ProcessGateway -> UpdateRecords -> NotifyCustomer

Thin DSL wrappers that delegate to app.services.payments for business logic.
"""

from __future__ import annotations

from tasker_core.step_handler.functional import depends_on, inputs, step_handler
from tasker_core.types import StepContext

from app.services import payments as svc
from app.services.types import (
    PaymentsProcessGatewayResult,
    PaymentsUpdateRecordsResult,
    PaymentsValidateEligibilityResult,
    ValidatePaymentEligibilityInput,
)


@step_handler("validate_eligibility")
@inputs(ValidatePaymentEligibilityInput)
def validate_eligibility(inputs: ValidatePaymentEligibilityInput, context: StepContext):
    # Input validation (required fields) is handled by the model's
    # @model_validator — see ValidatePaymentEligibilityInput in app/services/types.py.
    return svc.validate_eligibility(
        ValidatePaymentEligibilityInput(
            payment_id=inputs.payment_id or inputs.order_ref,
            refund_amount=inputs.refund_amount,
            refund_reason=inputs.refund_reason,
            partial_refund=inputs.partial_refund or False,
            order_ref=inputs.order_ref,
            customer_email=inputs.customer_email,
        )
    )


@step_handler("process_gateway")
@depends_on(eligibility=("validate_eligibility", PaymentsValidateEligibilityResult))
@inputs(ValidatePaymentEligibilityInput)
def process_gateway(
    eligibility: PaymentsValidateEligibilityResult,
    inputs: ValidatePaymentEligibilityInput,
    context: StepContext,
):
    return svc.process_gateway(
        eligibility=eligibility,
        refund_reason=inputs.refund_reason,
        partial_refund=inputs.partial_refund or False,
    )


@step_handler("update_records")
@depends_on(
    eligibility=("validate_eligibility", PaymentsValidateEligibilityResult),
    refund_result=("process_gateway", PaymentsProcessGatewayResult),
)
@inputs(ValidatePaymentEligibilityInput)
def update_records(
    eligibility: PaymentsValidateEligibilityResult,
    refund_result: PaymentsProcessGatewayResult,
    inputs: ValidatePaymentEligibilityInput,
    context: StepContext,
):
    return svc.update_records(
        eligibility=eligibility,
        refund_result=refund_result,
        refund_reason=inputs.refund_reason,
    )


@step_handler("notify_customer")
@depends_on(
    eligibility=("validate_eligibility", PaymentsValidateEligibilityResult),
    refund_result=("process_gateway", PaymentsProcessGatewayResult),
    records=("update_records", PaymentsUpdateRecordsResult),
)
@inputs(ValidatePaymentEligibilityInput)
def notify_customer(
    eligibility: PaymentsValidateEligibilityResult,
    refund_result: PaymentsProcessGatewayResult,
    records: PaymentsUpdateRecordsResult,
    inputs: ValidatePaymentEligibilityInput,
    context: StepContext,
):
    return svc.notify_customer(
        eligibility=eligibility,
        refund_result=refund_result,
        records=records,
        customer_email=inputs.customer_email,
    )
