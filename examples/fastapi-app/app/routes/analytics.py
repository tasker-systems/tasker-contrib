"""Data pipeline analytics routes demonstrating DAG workflow orchestration.

POST /analytics/jobs/ - Create an analytics job and kick off the 8-step DAG pipeline
GET  /analytics/jobs/{id} - Get analytics job details with current task status
"""

from __future__ import annotations

import logging
import uuid
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import AnalyticsJob
from app.schemas import CreateAnalyticsJobRequest, AnalyticsJobResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/jobs/", response_model=AnalyticsJobResponse, status_code=201)
async def create_analytics_job(
    request: CreateAnalyticsJobRequest,
    db: AsyncSession = Depends(get_db),
) -> AnalyticsJobResponse:
    """Create a data pipeline analytics job and start the DAG workflow.

    Creates a domain record then creates a Tasker task for the 8-step pipeline:
    3 parallel extracts -> 3 transforms -> aggregate metrics -> generate insights.
    """
    from tasker_core._tasker_core import client_create_task

    job = AnalyticsJob(
        source=request.source,
        dataset_url=request.dataset_url,
        status="pending",
    )
    db.add(job)
    await db.flush()

    task_request: dict[str, Any] = {
        "name": "analytics_pipeline",
        "namespace": "analytics",
        "version": "1.0.0",
        "context": {
            "job_id": job.id,
            "source": request.source,
            "dataset_url": request.dataset_url,
            "date_range_start": request.date_range_start,
            "date_range_end": request.date_range_end,
            "granularity": request.granularity,
        },
        "initiator": "fastapi-example",
        "source_system": "fastapi-example",
        "reason": "Data pipeline analytics job",
    }

    try:
        task_result = client_create_task(task_request)
        task_uuid = uuid.UUID(task_result["task_uuid"])
        job.task_uuid = task_uuid
        job.status = "processing"
        logger.info("Created task %s for analytics job %d", task_uuid, job.id)
    except Exception:
        logger.exception("Failed to create tasker task for analytics job %d", job.id)
        job.status = "task_creation_failed"

    await db.commit()
    await db.refresh(job)

    return AnalyticsJobResponse(
        id=job.id,
        source=job.source,
        dataset_url=job.dataset_url,
        status=job.status,
        task_uuid=job.task_uuid,
        created_at=job.created_at,
        updated_at=job.updated_at,
    )


@router.get("/jobs/{job_id}", response_model=AnalyticsJobResponse)
async def get_analytics_job(
    job_id: int,
    db: AsyncSession = Depends(get_db),
) -> AnalyticsJobResponse:
    """Get analytics job details with current workflow task status."""
    from tasker_core._tasker_core import client_get_task

    result = await db.execute(select(AnalyticsJob).where(AnalyticsJob.id == job_id))
    job = result.scalar_one_or_none()
    if job is None:
        raise HTTPException(status_code=404, detail="Analytics job not found")

    task_status = None
    if job.task_uuid:
        try:
            task_status = client_get_task(str(job.task_uuid))
        except Exception:
            logger.exception(
                "Failed to fetch task status for analytics job %d", job.id
            )

    return AnalyticsJobResponse(
        id=job.id,
        source=job.source,
        dataset_url=job.dataset_url,
        status=job.status,
        task_uuid=job.task_uuid,
        created_at=job.created_at,
        updated_at=job.updated_at,
        task_status=task_status,
    )
