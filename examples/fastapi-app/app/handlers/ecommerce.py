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
        cart_items = context.get_input("items") or context.get_input("cart_items")
        if not cart_items or not isinstance(cart_items, list):
            return StepHandlerResult.failure(
                message="Cart is empty or items field is missing",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="EMPTY_CART",
            )

        validated_items: list[dict[str, Any]] = []
        subtotal = 0.0

        for idx, item in enumerate(cart_items):
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
        # TAS-137: Use get_input() for task context access (cross-language standard)
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

        payment_id = f"pay_{uuid.uuid4().hex[:12]}"

        return StepHandlerResult.success(
            result={
                "payment_id": payment_id,
                "transaction_id": transaction_id,
                "authorization_code": authorization_code,
                "amount_charged": total,
                "currency": "USD",
                "payment_method_type": "card",
                "gateway_response": "approved",
                "status": "completed",
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
        updated_products: list[dict[str, Any]] = []
        inventory_changes: list[dict[str, Any]] = []
        total_items_reserved = 0

        for item in validated_items:
            reservation_id = f"res_{uuid.uuid4().hex[:12]}"
            quantity = item["quantity"]
            total_items_reserved += quantity

            updated_products.append(
                {
                    "product_id": item.get("sku"),
                    "name": item.get("name"),
                    "quantity_reserved": quantity,
                    "reservation_id": reservation_id,
                    "warehouse": "WH-EAST-01",
                    "status": "reserved",
                }
            )

            inventory_changes.append(
                {
                    "product_id": item.get("sku"),
                    "change_type": "reservation",
                    "quantity": -quantity,
                    "reason": "order_checkout",
                    "reservation_id": reservation_id,
                    "inventory_log_id": f"log_{uuid.uuid4().hex[:6]}",
                }
            )

        inventory_log_id = f"log_{uuid.uuid4().hex[:8]}"

        return StepHandlerResult.success(
            result={
                "updated_products": updated_products,
                "total_items_reserved": total_items_reserved,
                "inventory_changes": inventory_changes,
                "inventory_log_id": inventory_log_id,
                "updated_at": datetime.now(timezone.utc).isoformat(),
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
        # TAS-137: Use get_input() for task context access (cross-language standard)
        customer_email = context.get_input("customer_email")

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
        order_number = f"ORD-{datetime.now(timezone.utc).strftime('%Y%m%d')}-{uuid.uuid4().hex[:8].upper()}"
        total_amount = cart_result["total"]

        from datetime import timedelta

        estimated_delivery = (datetime.now(timezone.utc) + timedelta(days=7)).strftime(
            "%B %d, %Y"
        )

        return StepHandlerResult.success(
            result={
                "order_id": order_id,
                "order_number": order_number,
                "customer_email": customer_email,
                "items": cart_result["validated_items"],
                "item_count": cart_result["item_count"],
                "subtotal": cart_result["subtotal"],
                "tax": cart_result["tax"],
                "shipping": cart_result["shipping"],
                "total": cart_result["total"],
                "total_amount": total_amount,
                "payment_id": payment_result.get("payment_id"),
                "transaction_id": payment_result["transaction_id"],
                "authorization_code": payment_result.get("authorization_code"),
                "updated_products": inventory_result.get("updated_products"),
                "inventory_log_id": inventory_result.get("inventory_log_id"),
                "status": "confirmed",
                "created_at": datetime.now(timezone.utc).isoformat(),
                "estimated_delivery": estimated_delivery,
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
        # TAS-137: Use get_input() for task context access (cross-language standard)
        customer_email = context.get_input("customer_email")

        order_result = context.get_dependency_result("create_order")
        cart_validation = context.get_dependency_result("validate_cart")

        if order_result is None:
            return StepHandlerResult.failure(
                message="Missing create_order dependency result",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        message_id = f"msg_{uuid.uuid4().hex[:16]}"
        customer_email = customer_email or order_result.get("customer_email", "unknown@example.com")
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
                "email_sent": True,
                "recipient": customer_email,
                "email_type": "order_confirmation",
                "message_id": message_id,
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
