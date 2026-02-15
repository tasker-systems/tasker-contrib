"""E-commerce order routes demonstrating sequential workflow orchestration.

POST /orders/ - Create an order and kick off the 5-step processing workflow
GET  /orders/{id} - Get order details with current task status
"""

from __future__ import annotations

import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import Order
from app.schemas import CreateOrderRequest, OrderResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/", response_model=OrderResponse, status_code=201)
async def create_order(
    request: CreateOrderRequest,
    db: AsyncSession = Depends(get_db),
) -> OrderResponse:
    """Create an e-commerce order and start the processing workflow.

    Creates a domain record in the app database, then creates a Tasker task
    to orchestrate the 5-step processing pipeline: validate cart, process
    payment, update inventory, create order, send confirmation.
    """
    from tasker_core.client import TaskerClient

    # Create the domain record
    order = Order(
        customer_email=request.customer_email,
        items=[item.model_dump() for item in request.items],
        status="pending",
    )
    db.add(order)
    await db.flush()

    # Create the tasker task
    client = TaskerClient(initiator="fastapi-example", source_system="fastapi-example")
    try:
        task_response = client.create_task(
            "ecommerce_order_processing",
            namespace="ecommerce_py",
            context={
                "order_id": order.id,
                "customer_email": request.customer_email,
                "items": [item.model_dump() for item in request.items],
                "payment_token": request.payment_token,
                "shipping_address": request.shipping_address,
            },
            reason="E-commerce order processing",
        )
        task_uuid = uuid.UUID(task_response.task_uuid)
        order.task_uuid = task_uuid
        order.status = "processing"
        logger.info("Created task %s for order %d", task_uuid, order.id)
    except Exception:
        logger.exception("Failed to create tasker task for order %d", order.id)
        order.status = "task_creation_failed"

    await db.commit()
    await db.refresh(order)

    return OrderResponse(
        id=order.id,
        customer_email=order.customer_email,
        items=order.items,
        total=float(order.total) if order.total else None,
        status=order.status,
        task_uuid=order.task_uuid,
        created_at=order.created_at,
        updated_at=order.updated_at,
    )


@router.get("/{order_id}", response_model=OrderResponse)
async def get_order(
    order_id: int,
    db: AsyncSession = Depends(get_db),
) -> OrderResponse:
    """Get order details with current workflow task status."""
    from tasker_core.client import TaskerClient

    result = await db.execute(select(Order).where(Order.id == order_id))
    order = result.scalar_one_or_none()
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")

    task_status = None
    if order.task_uuid:
        try:
            client = TaskerClient(initiator="fastapi-example", source_system="fastapi-example")
            task_status = client.get_task(str(order.task_uuid)).__dict__
        except Exception:
            logger.exception("Failed to fetch task status for order %d", order.id)

    return OrderResponse(
        id=order.id,
        customer_email=order.customer_email,
        items=order.items,
        total=float(order.total) if order.total else None,
        status=order.status,
        task_uuid=order.task_uuid,
        created_at=order.created_at,
        updated_at=order.updated_at,
        task_status=task_status,
    )
