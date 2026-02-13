"""Pydantic v2 request/response schemas for the FastAPI example app."""

from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# E-commerce Order
# ---------------------------------------------------------------------------


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
    """Response for an order with optional task status."""

    id: int
    customer_email: str
    items: list[dict[str, Any]]
    total: float | None = None
    status: str
    task_uuid: UUID | None = None
    created_at: datetime
    updated_at: datetime
    task_status: dict[str, Any] | None = None


# ---------------------------------------------------------------------------
# Data Pipeline Analytics
# ---------------------------------------------------------------------------


class CreateAnalyticsJobRequest(BaseModel):
    """Request body for creating an analytics pipeline job."""

    source: str = Field(
        ..., description="Data source identifier (e.g., 'sales', 'web_traffic')"
    )
    dataset_url: str | None = Field(
        default=None, description="URL to the dataset (optional)"
    )
    date_range_start: str = Field(
        default="2026-01-01", description="Analysis start date"
    )
    date_range_end: str = Field(default="2026-01-31", description="Analysis end date")
    granularity: str = Field(
        default="daily",
        description="Time granularity (hourly, daily, weekly, monthly)",
    )


class AnalyticsJobResponse(BaseModel):
    """Response for an analytics job with optional task status."""

    id: int
    source: str
    dataset_url: str | None = None
    status: str
    task_uuid: UUID | None = None
    created_at: datetime
    updated_at: datetime
    task_status: dict[str, Any] | None = None


# ---------------------------------------------------------------------------
# Microservices User Registration
# ---------------------------------------------------------------------------


class CreateServiceRequest(BaseModel):
    """Request body for creating a user registration request."""

    user_id: str = Field(..., description="Unique user identifier")
    request_type: str = Field(
        default="user_registration", description="Type of service request"
    )
    email: str = Field(..., description="User email address")
    full_name: str = Field(..., description="User full name")
    plan: str = Field(
        default="starter", description="Subscription plan (starter, professional, enterprise)"
    )


class ServiceRequestResponse(BaseModel):
    """Response for a service request with optional task status."""

    id: int
    user_id: str
    request_type: str
    status: str
    result: dict[str, Any] | None = None
    task_uuid: UUID | None = None
    created_at: datetime
    updated_at: datetime
    task_status: dict[str, Any] | None = None


# ---------------------------------------------------------------------------
# Team Scaling / Compliance
# ---------------------------------------------------------------------------


class CreateComplianceCheckRequest(BaseModel):
    """Request body for creating a compliance / refund check."""

    order_ref: str = Field(..., description="Original order reference")
    namespace: str = Field(
        default="customer_success",
        description="Namespace (customer_success or payments)",
    )
    reason: str = Field(default="customer_request", description="Reason for refund")
    amount: float = Field(..., gt=0, description="Refund amount requested")
    customer_email: str = Field(..., description="Customer email address")


class ComplianceCheckResponse(BaseModel):
    """Response for a compliance check with optional task status."""

    id: int
    order_ref: str
    namespace: str
    status: str
    task_uuid: UUID | None = None
    created_at: datetime
    updated_at: datetime
    task_status: dict[str, Any] | None = None
