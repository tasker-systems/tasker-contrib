"""E-commerce order processing step handlers.

5 sequential steps demonstrating a linear pipeline:
  ValidateCart -> ProcessPayment -> UpdateInventory -> CreateOrder -> SendConfirmation

Each handler receives data from the task context and/or upstream dependency
results, performs simulated business logic, and returns structured output
for downstream steps.
"""

from __future__ import annotations

import hashlib
import uuid
from datetime import datetime, timezone
from typing import Any

from tasker_core import ErrorType, StepContext, StepHandler, StepHandlerResult


class ValidateCartHandler(StepHandler):
    """Validate cart items and calculate order totals.

    Reads item list from task context, verifies each item has required fields,
    calculates subtotal, tax (8%), shipping, and grand total.
    """

    handler_name = "validate_cart"
    handler_version = "1.0.0"

    TAX_RATE = 0.08
    FREE_SHIPPING_THRESHOLD = 100.00
    STANDARD_SHIPPING = 9.99

    def call(self, context: StepContext) -> StepHandlerResult:
        items = context.get_input("items")
        if not items or not isinstance(items, list):
            return StepHandlerResult.failure(
                message="Cart is empty or items field is missing",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="EMPTY_CART",
            )

        validated_items: list[dict[str, Any]] = []
        subtotal = 0.0

        for idx, item in enumerate(items):
            sku = item.get("sku")
            name = item.get("name")
            quantity = item.get("quantity", 0)
            unit_price = item.get("unit_price", 0.0)

            if not sku or not name:
                return StepHandlerResult.failure(
                    message=f"Item at index {idx} missing sku or name",
                    error_type=ErrorType.VALIDATION_ERROR,
                    retryable=False,
                    error_code="INVALID_ITEM",
                )

            if quantity < 1:
                return StepHandlerResult.failure(
                    message=f"Item '{sku}' has invalid quantity: {quantity}",
                    error_type=ErrorType.VALIDATION_ERROR,
                    retryable=False,
                    error_code="INVALID_QUANTITY",
                )

            if unit_price <= 0:
                return StepHandlerResult.failure(
                    message=f"Item '{sku}' has invalid price: {unit_price}",
                    error_type=ErrorType.VALIDATION_ERROR,
                    retryable=False,
                    error_code="INVALID_PRICE",
                )

            line_total = round(quantity * unit_price, 2)
            subtotal += line_total
            validated_items.append(
                {
                    "sku": sku,
                    "name": name,
                    "quantity": quantity,
                    "unit_price": unit_price,
                    "line_total": line_total,
                }
            )

        subtotal = round(subtotal, 2)
        tax = round(subtotal * self.TAX_RATE, 2)
        shipping = (
            0.0 if subtotal >= self.FREE_SHIPPING_THRESHOLD else self.STANDARD_SHIPPING
        )
        total = round(subtotal + tax + shipping, 2)

        return StepHandlerResult.success(
            result={
                "validated_items": validated_items,
                "item_count": len(validated_items),
                "subtotal": subtotal,
                "tax": tax,
                "tax_rate": self.TAX_RATE,
                "shipping": shipping,
                "total": total,
                "validated_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"items_validated": len(validated_items)},
        )


class ProcessPaymentHandler(StepHandler):
    """Process payment through simulated payment gateway.

    Reads payment token from task context and total from the validate_cart
    dependency. Simulates gateway authorization with test tokens.
    """

    handler_name = "process_payment"
    handler_version = "1.0.0"

    DECLINED_TOKENS = {"tok_test_declined", "tok_test_insufficient_funds"}
    ERROR_TOKENS = {"tok_test_gateway_error", "tok_test_timeout"}

    def call(self, context: StepContext) -> StepHandlerResult:
        payment_token = context.get_input("payment_token") or "tok_test_success"

        cart_result = context.get_dependency_result("validate_cart")
        if cart_result is None:
            return StepHandlerResult.failure(
                message="Missing validate_cart dependency result",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        total = cart_result.get("total", 0.0)

        if payment_token in self.DECLINED_TOKENS:
            return StepHandlerResult.failure(
                message=f"Payment declined for token {payment_token}",
                error_type=ErrorType.PERMANENT_ERROR,
                retryable=False,
                error_code="PAYMENT_DECLINED",
            )

        if payment_token in self.ERROR_TOKENS:
            return StepHandlerResult.failure(
                message="Payment gateway returned an error, will retry",
                error_type=ErrorType.RETRYABLE_ERROR,
                retryable=True,
                error_code="GATEWAY_ERROR",
            )

        transaction_id = f"txn_{uuid.uuid4().hex[:16]}"
        authorization_code = hashlib.sha256(
            f"{payment_token}:{total}:{transaction_id}".encode()
        ).hexdigest()[:12].upper()

        return StepHandlerResult.success(
            result={
                "transaction_id": transaction_id,
                "authorization_code": authorization_code,
                "amount_charged": total,
                "currency": "USD",
                "payment_method": "card",
                "gateway_response": "approved",
                "processed_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={
                "gateway": "simulated",
                "token_prefix": payment_token[:8],
            },
        )


class UpdateInventoryHandler(StepHandler):
    """Create inventory reservations for validated cart items.

    Reads validated items from the validate_cart dependency and creates
    simulated inventory reservations with unique reservation IDs.
    """

    handler_name = "update_inventory"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        cart_result = context.get_dependency_result("validate_cart")
        if cart_result is None:
            return StepHandlerResult.failure(
                message="Missing validate_cart dependency result",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        validated_items = cart_result.get("validated_items", [])
        reservations: list[dict[str, Any]] = []
        total_units_reserved = 0

        for item in validated_items:
            reservation_id = f"res_{uuid.uuid4().hex[:12]}"
            quantity = item["quantity"]
            total_units_reserved += quantity

            reservations.append(
                {
                    "reservation_id": reservation_id,
                    "sku": item["sku"],
                    "quantity_reserved": quantity,
                    "warehouse": "WH-EAST-01",
                    "status": "reserved",
                    "expires_at": "2026-02-13T00:00:00Z",
                }
            )

        return StepHandlerResult.success(
            result={
                "reservations": reservations,
                "total_units_reserved": total_units_reserved,
                "reservation_count": len(reservations),
                "reserved_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"warehouse": "WH-EAST-01"},
        )


class CreateOrderHandler(StepHandler):
    """Create the final order record by aggregating all upstream data.

    Combines results from validate_cart, process_payment, and update_inventory
    into a consolidated order record with a generated order ID.
    """

    handler_name = "create_order"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        cart_result = context.get_dependency_result("validate_cart")
        payment_result = context.get_dependency_result("process_payment")
        inventory_result = context.get_dependency_result("update_inventory")

        if not all([cart_result, payment_result, inventory_result]):
            return StepHandlerResult.failure(
                message="Missing one or more upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        order_id = f"ORD-{uuid.uuid4().hex[:8].upper()}"
        customer_email = context.get_input("customer_email")
        shipping_address = context.get_input("shipping_address")

        return StepHandlerResult.success(
            result={
                "order_id": order_id,
                "customer_email": customer_email,
                "shipping_address": shipping_address,
                "items": cart_result["validated_items"],
                "item_count": cart_result["item_count"],
                "subtotal": cart_result["subtotal"],
                "tax": cart_result["tax"],
                "shipping": cart_result["shipping"],
                "total": cart_result["total"],
                "transaction_id": payment_result["transaction_id"],
                "authorization_code": payment_result["authorization_code"],
                "reservations": inventory_result["reservations"],
                "status": "confirmed",
                "created_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"order_id": order_id},
        )


class SendConfirmationHandler(StepHandler):
    """Send order confirmation email to customer.

    Reads the completed order from the create_order dependency and simulates
    sending a confirmation email with order details.
    """

    handler_name = "send_confirmation"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        order_result = context.get_dependency_result("create_order")
        if order_result is None:
            return StepHandlerResult.failure(
                message="Missing create_order dependency result",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        message_id = f"msg_{uuid.uuid4().hex[:16]}"
        customer_email = order_result.get("customer_email", "unknown@example.com")
        order_id = order_result.get("order_id", "UNKNOWN")
        total = order_result.get("total", 0.0)
        item_count = order_result.get("item_count", 0)

        subject = f"Order Confirmation - {order_id}"
        body_preview = (
            f"Thank you for your order! Your order {order_id} containing "
            f"{item_count} item(s) totalling ${total:.2f} has been confirmed. "
            f"We'll notify you when your items ship."
        )

        return StepHandlerResult.success(
            result={
                "message_id": message_id,
                "recipient": customer_email,
                "subject": subject,
                "body_preview": body_preview,
                "channel": "email",
                "template": "order_confirmation_v2",
                "status": "sent",
                "sent_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={
                "email_provider": "simulated",
                "template_version": "2.0",
            },
        )
