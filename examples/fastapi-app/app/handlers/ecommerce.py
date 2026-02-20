"""E-commerce order processing step handlers.

5 sequential steps demonstrating a linear pipeline:
  ValidateCart -> ProcessPayment -> UpdateInventory -> CreateOrder -> SendConfirmation

Thin DSL wrappers that delegate to app.services.ecommerce for business logic.
"""

from __future__ import annotations

from tasker_core.step_handler.functional import depends_on, inputs, step_handler
from tasker_core.types import StepContext

from app.services import ecommerce as svc
from app.services.types import (
    EcommerceCreateOrderResult,
    EcommerceOrderInput,
    EcommerceProcessPaymentResult,
    EcommerceUpdateInventoryResult,
    EcommerceValidateCartResult,
)


@step_handler("validate_cart")
@inputs(EcommerceOrderInput)
def validate_cart(inputs: EcommerceOrderInput, context: StepContext):
    return svc.validate_cart_items(inputs.resolved_items)


@step_handler("process_payment")
@depends_on(cart_result=("validate_cart", EcommerceValidateCartResult))
@inputs(EcommerceOrderInput)
def process_payment(
    cart_result: EcommerceValidateCartResult,
    inputs: EcommerceOrderInput,
    context: StepContext,
):
    return svc.process_payment(
        payment_token=inputs.payment_token,
        total=cart_result.total or 0.0,
    )


@step_handler("update_inventory")
@depends_on(cart_result=("validate_cart", EcommerceValidateCartResult))
def update_inventory(cart_result: EcommerceValidateCartResult, context: StepContext):
    return svc.update_inventory(cart_result.validated_items or [])


@step_handler("create_order")
@depends_on(
    cart_result=("validate_cart", EcommerceValidateCartResult),
    payment_result=("process_payment", EcommerceProcessPaymentResult),
    inventory_result=("update_inventory", EcommerceUpdateInventoryResult),
)
@inputs(EcommerceOrderInput)
def create_order(
    cart_result: EcommerceValidateCartResult,
    payment_result: EcommerceProcessPaymentResult,
    inventory_result: EcommerceUpdateInventoryResult,
    inputs: EcommerceOrderInput,
    context: StepContext,
):
    return svc.create_order(
        cart=cart_result,
        payment=payment_result,
        inventory=inventory_result,
        customer_email=inputs.customer_email,
    )


@step_handler("send_confirmation")
@depends_on(order_result=("create_order", EcommerceCreateOrderResult))
@inputs(EcommerceOrderInput)
def send_confirmation(
    order_result: EcommerceCreateOrderResult,
    inputs: EcommerceOrderInput,
    context: StepContext,
):
    return svc.send_confirmation(order=order_result, customer_email=inputs.customer_email)
