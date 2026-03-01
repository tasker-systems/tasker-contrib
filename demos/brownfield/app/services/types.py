"""Type definitions for e-commerce service functions.

Result types describe what each service function returns.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel


class ValidationError(ValueError):
    """Raised when input validation fails permanently."""

    pass


# ---------------------------------------------------------------------------
# Cart / order line item
# ---------------------------------------------------------------------------


class EcommerceCartItem(BaseModel):
    """A validated cart/order line item."""

    sku: str
    name: str
    quantity: int
    unit_price: float
    line_total: float


# ---------------------------------------------------------------------------
# Result types — one per service function
# ---------------------------------------------------------------------------


class EcommerceValidateCartResult(BaseModel):
    validated_items: list[EcommerceCartItem]
    item_count: int
    subtotal: float
    tax: float
    tax_rate: float
    shipping: float
    total: float
    validated_at: str


class EcommerceProcessPaymentResult(BaseModel):
    payment_id: str
    transaction_id: str
    authorization_code: str
    amount_charged: float
    currency: str
    payment_method_type: str
    gateway_response: str | None = None
    status: str
    processed_at: str


class EcommerceUpdateInventoryResult(BaseModel):
    updated_products: list[dict[str, Any]]
    total_items_reserved: int
    inventory_changes: list[dict[str, Any]] | None = None
    inventory_log_id: str
    updated_at: str


class EcommerceCreateOrderResult(BaseModel):
    order_id: str
    order_number: str
    customer_email: str
    items: list[EcommerceCartItem]
    item_count: int
    subtotal: float
    tax: float
    shipping: float
    total: float
    total_amount: float
    payment_id: str
    transaction_id: str
    authorization_code: str
    updated_products: list[dict[str, Any]] | None = None
    inventory_log_id: str
    status: str
    created_at: str
    estimated_delivery: str


class EcommerceSendConfirmationResult(BaseModel):
    email_sent: bool
    recipient: str
    email_type: str | None = None
    message_id: str
    subject: str
    body_preview: str | None = None
    channel: str
    template: str
    status: str
    sent_at: str
