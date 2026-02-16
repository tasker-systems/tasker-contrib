"""Team scaling / compliance routes demonstrating namespace isolation.

POST /compliance/checks/ - Create a compliance check spanning 2 namespaces
GET  /compliance/checks/{id} - Get compliance check details with task status

This demonstrates the team-scaling pattern where CustomerSuccess and Payments
teams each own their own namespace with independent step handlers.
"""

from __future__ import annotations

import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import ComplianceCheck
from app.schemas import CreateComplianceCheckRequest, ComplianceCheckResponse

logger = logging.getLogger(__name__)
router = APIRouter()


TEMPLATE_MAP = {
    "customer_success_py": "process_refund",
    "payments_py": "process_refund",
}


@router.post("/checks/", response_model=ComplianceCheckResponse, status_code=201)
async def create_compliance_check(
    request: CreateComplianceCheckRequest,
    db: AsyncSession = Depends(get_db),
) -> ComplianceCheckResponse:
    """Create a compliance check and start the namespace-isolated workflow.

    Depending on the namespace, either the CustomerSuccess (5 steps) or
    Payments (4 steps) workflow is started. Each namespace has its own
    handlers, demonstrating team scaling with independent ownership.
    """
    from tasker_core.client import TaskerClient

    check = ComplianceCheck(
        order_ref=request.order_ref,
        namespace=request.namespace,
        status="pending",
    )
    db.add(check)
    await db.flush()

    template_name = TEMPLATE_MAP.get(request.namespace)
    if template_name is None:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown namespace: {request.namespace}. "
            f"Valid: {', '.join(TEMPLATE_MAP.keys())}",
        )

    client = TaskerClient(initiator="fastapi-example", source_system="fastapi-example")
    try:
        task_response = client.create_task(
            template_name,
            namespace=request.namespace,
            context={
                "check_id": check.id,
                "order_ref": request.order_ref,
                "reason": request.reason,
                "amount": request.amount,
                "customer_email": request.customer_email,
            },
            reason=f"Compliance check for order {request.order_ref}",
        )
        task_uuid = uuid.UUID(task_response.task_uuid)
        check.task_uuid = task_uuid
        check.status = "processing"
        logger.info("Created task %s for compliance check %d", task_uuid, check.id)
    except Exception:
        logger.exception(
            "Failed to create tasker task for compliance check %d", check.id
        )
        check.status = "task_creation_failed"

    await db.commit()
    await db.refresh(check)

    return ComplianceCheckResponse(
        id=check.id,
        order_ref=check.order_ref,
        namespace=check.namespace,
        status=check.status,
        task_uuid=check.task_uuid,
        created_at=check.created_at,
        updated_at=check.updated_at,
    )


@router.get("/checks/{check_id}", response_model=ComplianceCheckResponse)
async def get_compliance_check(
    check_id: int,
    db: AsyncSession = Depends(get_db),
) -> ComplianceCheckResponse:
    """Get compliance check details with current workflow task status."""
    from tasker_core.client import TaskerClient

    result = await db.execute(
        select(ComplianceCheck).where(ComplianceCheck.id == check_id)
    )
    check = result.scalar_one_or_none()
    if check is None:
        raise HTTPException(status_code=404, detail="Compliance check not found")

    task_status = None
    if check.task_uuid:
        try:
            client = TaskerClient(initiator="fastapi-example", source_system="fastapi-example")
            task_status = client.get_task(str(check.task_uuid)).__dict__
        except Exception:
            logger.exception(
                "Failed to fetch task status for compliance check %d", check.id
            )

    return ComplianceCheckResponse(
        id=check.id,
        order_ref=check.order_ref,
        namespace=check.namespace,
        status=check.status,
        task_uuid=check.task_uuid,
        created_at=check.created_at,
        updated_at=check.updated_at,
        task_status=task_status,
    )
