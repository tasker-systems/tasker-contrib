"""Pydantic v2 request/response schemas."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class OrderItem(BaseModel):
    """A single item in a cart."""

    sku: str = Field(..., description="Product SKU")
    name: str = Field(..., description="Product name")
    quantity: int = Field(..., ge=1, description="Quantity ordered")
    unit_price: float = Field(..., gt=0, description="Price per unit")


class CreateOrderRequest(BaseModel):
    """Request body for creating an e-commerce order."""

    customer_email: str = Field(..., description="Customer email address")
    items: list[OrderItem] = Field(..., min_length=1, description="Cart items")
    payment_token: str = Field(
        default="tok_test_success", description="Payment gateway token"
    )
    shipping_address: str = Field(
        default="123 Main St, Anytown, US 12345", description="Shipping address"
    )


class OrderResponse(BaseModel):
    """Response for an order."""

    id: int
    customer_email: str
    items: list[dict[str, Any]]
    total: float | None = None
    status: str
    created_at: datetime
    updated_at: datetime
