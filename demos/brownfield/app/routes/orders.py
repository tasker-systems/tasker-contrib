"""E-commerce order routes.

POST /orders/ - Create an order by running all 5 processing steps sequentially
GET  /orders/{id} - Get order details
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import Order
from app.schemas import CreateOrderRequest, OrderResponse
from app.services import ecommerce as svc

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/", response_model=OrderResponse, status_code=201)
async def create_order(
    request: CreateOrderRequest,
    db: AsyncSession = Depends(get_db),
) -> OrderResponse:
    """Process an order synchronously through all 5 steps.

    Steps run sequentially in a single request:
      1. Validate cart items and calculate totals
      2. Process payment
      3. Update inventory reservations
      4. Create the order record
      5. Send confirmation email
    """
    # Step 1: Validate cart
    cart = svc.validate_cart_items([item.model_dump() for item in request.items])

    # Step 2: Process payment
    payment = svc.process_payment(
        payment_token=request.payment_token,
        total=cart.total,
    )

    # Step 3: Update inventory
    inventory = svc.update_inventory(cart.validated_items)

    # Step 4: Create order
    order_result = svc.create_order(
        cart=cart,
        payment=payment,
        inventory=inventory,
        customer_email=request.customer_email,
    )

    # Step 5: Send confirmation
    svc.send_confirmation(
        order=order_result,
        customer_email=request.customer_email,
    )

    # Persist to database
    order = Order(
        customer_email=request.customer_email,
        items=[item.model_dump() for item in request.items],
        total=cart.total,
        status="confirmed",
    )
    db.add(order)
    await db.flush()
    await db.refresh(order)

    return OrderResponse(
        id=order.id,
        customer_email=order.customer_email,
        items=order.items,
        total=float(order.total) if order.total else None,
        status=order.status,
        created_at=order.created_at,
        updated_at=order.updated_at,
    )


@router.get("/{order_id}", response_model=OrderResponse)
async def get_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
) -> OrderResponse:
    """Get order details."""
    result = await db.execute(select(Order).where(Order.id == order_id))
    order = result.scalar_one_or_none()
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")

    return OrderResponse(
        id=order.id,
        customer_email=order.customer_email,
        items=order.items,
        total=float(order.total) if order.total else None,
        status=order.status,
        created_at=order.created_at,
        updated_at=order.updated_at,
    )
