"""E-commerce business logic.

Pure functions that validate carts, process payments, manage inventory,
create orders, and send confirmations. No Tasker types — just plain
dicts in, typed models out.
"""

from __future__ import annotations

import hashlib
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from tasker_core.errors import PermanentError, RetryableError

from .types import (
    EcommerceCreateOrderResult,
    EcommerceProcessPaymentResult,
    EcommerceSendConfirmationResult,
    EcommerceUpdateInventoryResult,
    EcommerceValidateCartResult,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

TAX_RATE = 0.08
FREE_SHIPPING_THRESHOLD = 100.00
STANDARD_SHIPPING = 9.99

DECLINED_TOKENS = {"tok_test_declined", "tok_test_insufficient_funds"}
ERROR_TOKENS = {"tok_test_gateway_error", "tok_test_timeout"}


# ---------------------------------------------------------------------------
# Service functions
# ---------------------------------------------------------------------------


def validate_cart_items(
    cart_items: list[dict[str, Any]] | None,
) -> EcommerceValidateCartResult:
    """Validate cart items and calculate order totals."""
    if not cart_items or not isinstance(cart_items, list):
        raise PermanentError("Cart is empty or items field is missing")

    validated_items: list[dict[str, Any]] = []
    subtotal = 0.0

    for idx, item in enumerate(cart_items):
        sku = item.get("sku")
        name = item.get("name")
        quantity = item.get("quantity", 0)
        unit_price = item.get("unit_price", 0.0)

        if not sku or not name:
            raise PermanentError(f"Item at index {idx} missing sku or name")

        if quantity < 1:
            raise PermanentError(f"Item '{sku}' has invalid quantity: {quantity}")

        if unit_price <= 0:
            raise PermanentError(f"Item '{sku}' has invalid price: {unit_price}")

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
    tax = round(subtotal * TAX_RATE, 2)
    shipping = 0.0 if subtotal >= FREE_SHIPPING_THRESHOLD else STANDARD_SHIPPING
    total = round(subtotal + tax + shipping, 2)

    return EcommerceValidateCartResult(
        validated_items=validated_items,
        item_count=len(validated_items),
        subtotal=subtotal,
        tax=tax,
        tax_rate=TAX_RATE,
        shipping=shipping,
        total=total,
        validated_at=datetime.now(timezone.utc).isoformat(),
    )


def process_payment(
    payment_token: str | None,
    total: float,
) -> EcommerceProcessPaymentResult:
    """Process payment through simulated payment gateway."""
    payment_token = payment_token or "tok_test_success"

    if payment_token in DECLINED_TOKENS:
        raise PermanentError(f"Payment declined for token {payment_token}")

    if payment_token in ERROR_TOKENS:
        raise RetryableError("Payment gateway returned an error, will retry")

    transaction_id = f"txn_{uuid.uuid4().hex[:16]}"
    authorization_code = hashlib.sha256(
        f"{payment_token}:{total}:{transaction_id}".encode()
    ).hexdigest()[:12].upper()
    payment_id = f"pay_{uuid.uuid4().hex[:12]}"

    return EcommerceProcessPaymentResult(
        payment_id=payment_id,
        transaction_id=transaction_id,
        authorization_code=authorization_code,
        amount_charged=total,
        currency="USD",
        payment_method_type="card",
        gateway_response="approved",
        status="completed",
        processed_at=datetime.now(timezone.utc).isoformat(),
    )


def update_inventory(
    validated_items: list[dict[str, Any]],
) -> EcommerceUpdateInventoryResult:
    """Create inventory reservations for validated cart items."""
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

    return EcommerceUpdateInventoryResult(
        updated_products=updated_products,
        total_items_reserved=total_items_reserved,
        inventory_changes=inventory_changes,
        inventory_log_id=inventory_log_id,
        updated_at=datetime.now(timezone.utc).isoformat(),
    )


def create_order(
    cart: EcommerceValidateCartResult,
    payment: EcommerceProcessPaymentResult,
    inventory: EcommerceUpdateInventoryResult,
    customer_email: str | None,
) -> EcommerceCreateOrderResult:
    """Create the final order record by aggregating upstream data."""
    order_id = f"ORD-{uuid.uuid4().hex[:8].upper()}"
    order_number = f"ORD-{datetime.now(timezone.utc).strftime('%Y%m%d')}-{uuid.uuid4().hex[:8].upper()}"
    total_amount = cart.total
    estimated_delivery = (datetime.now(timezone.utc) + timedelta(days=7)).strftime(
        "%B %d, %Y"
    )

    return EcommerceCreateOrderResult(
        order_id=order_id,
        order_number=order_number,
        customer_email=customer_email,
        items=cart.validated_items,
        item_count=cart.item_count,
        subtotal=cart.subtotal,
        tax=cart.tax,
        shipping=cart.shipping,
        total=cart.total,
        total_amount=total_amount,
        payment_id=payment.payment_id,
        transaction_id=payment.transaction_id,
        authorization_code=payment.authorization_code,
        updated_products=inventory.updated_products,
        inventory_log_id=inventory.inventory_log_id,
        status="confirmed",
        created_at=datetime.now(timezone.utc).isoformat(),
        estimated_delivery=estimated_delivery,
    )


def send_confirmation(
    order: EcommerceCreateOrderResult,
    customer_email: str | None,
) -> EcommerceSendConfirmationResult:
    """Send order confirmation email to customer."""
    message_id = f"msg_{uuid.uuid4().hex[:16]}"
    customer_email = customer_email or order.customer_email or "unknown@example.com"
    order_id = order.order_id or "UNKNOWN"
    total = order.total or 0.0
    item_count = order.item_count or 0

    subject = f"Order Confirmation - {order_id}"
    body_preview = (
        f"Thank you for your order! Your order {order_id} containing "
        f"{item_count} item(s) totalling ${total:.2f} has been confirmed. "
        f"We'll notify you when your items ship."
    )

    return EcommerceSendConfirmationResult(
        email_sent=True,
        recipient=customer_email,
        email_type="order_confirmation",
        message_id=message_id,
        subject=subject,
        body_preview=body_preview,
        channel="email",
        template="order_confirmation_v2",
        status="sent",
        sent_at=datetime.now(timezone.utc).isoformat(),
    )
