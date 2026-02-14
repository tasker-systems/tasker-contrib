"""Microservices user registration routes demonstrating diamond dependency pattern.

POST /services/requests/ - Create a service request and kick off the 5-step diamond workflow
GET  /services/requests/{id} - Get service request details with current task status
"""

from __future__ import annotations

import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import ServiceRequest
from app.schemas import CreateServiceRequest, ServiceRequestResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/requests/", response_model=ServiceRequestResponse, status_code=201)
async def create_service_request(
    request: CreateServiceRequest,
    db: AsyncSession = Depends(get_db),
) -> ServiceRequestResponse:
    """Create a user registration request and start the diamond workflow.

    Creates a domain record then creates a Tasker task for the 5-step pipeline:
    CreateUser -> (SetupBilling || InitPreferences) -> SendWelcome -> UpdateStatus.
    """
    from tasker_core.client import TaskerClient

    svc_request = ServiceRequest(
        user_id=request.user_id,
        request_type=request.request_type,
        status="pending",
    )
    db.add(svc_request)
    await db.flush()

    client = TaskerClient(initiator="fastapi-example", source_system="fastapi-example")
    try:
        task_response = client.create_task(
            "user_registration",
            namespace="microservices",
            context={
                "request_id": svc_request.id,
                "user_id": request.user_id,
                "email": request.email,
                "full_name": request.full_name,
                "plan": request.plan,
            },
            reason="User registration",
        )
        task_uuid = uuid.UUID(task_response.task_uuid)
        svc_request.task_uuid = task_uuid
        svc_request.status = "processing"
        logger.info(
            "Created task %s for service request %d", task_uuid, svc_request.id
        )
    except Exception:
        logger.exception(
            "Failed to create tasker task for service request %d", svc_request.id
        )
        svc_request.status = "task_creation_failed"

    await db.commit()
    await db.refresh(svc_request)

    return ServiceRequestResponse(
        id=svc_request.id,
        user_id=svc_request.user_id,
        request_type=svc_request.request_type,
        status=svc_request.status,
        result=svc_request.result,
        task_uuid=svc_request.task_uuid,
        created_at=svc_request.created_at,
        updated_at=svc_request.updated_at,
    )


@router.get("/requests/{request_id}", response_model=ServiceRequestResponse)
async def get_service_request(
    request_id: int,
    db: AsyncSession = Depends(get_db),
) -> ServiceRequestResponse:
    """Get service request details with current workflow task status."""
    from tasker_core.client import TaskerClient

    result = await db.execute(
        select(ServiceRequest).where(ServiceRequest.id == request_id)
    )
    svc_request = result.scalar_one_or_none()
    if svc_request is None:
        raise HTTPException(status_code=404, detail="Service request not found")

    task_status = None
    if svc_request.task_uuid:
        try:
            client = TaskerClient(initiator="fastapi-example", source_system="fastapi-example")
            task_status = client.get_task(str(svc_request.task_uuid))
        except Exception:
            logger.exception(
                "Failed to fetch task status for service request %d", svc_request.id
            )

    return ServiceRequestResponse(
        id=svc_request.id,
        user_id=svc_request.user_id,
        request_type=svc_request.request_type,
        status=svc_request.status,
        result=svc_request.result,
        task_uuid=svc_request.task_uuid,
        created_at=svc_request.created_at,
        updated_at=svc_request.updated_at,
        task_status=task_status,
    )
