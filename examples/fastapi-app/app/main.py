"""FastAPI application demonstrating Tasker workflow orchestration patterns.

This app bootstraps a tasker-core worker at startup (with web/gRPC disabled)
and exposes framework-native HTTP endpoints for creating and querying workflows.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from collections.abc import AsyncGenerator

from dotenv import load_dotenv
from fastapi import FastAPI

load_dotenv()

from app.routes import analytics, compliance, orders, services

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan: bootstrap tasker worker on startup, stop on shutdown."""
    from tasker_core import bootstrap_worker, stop_worker

    logger.info("Bootstrapping tasker worker...")
    result = bootstrap_worker()
    logger.info(
        "Tasker worker started: worker_id=%s, status=%s",
        result.worker_id,
        result.status,
    )

    yield

    logger.info("Stopping tasker worker...")
    stop_worker()
    logger.info("Tasker worker stopped")


app = FastAPI(
    title="Tasker FastAPI Example",
    description=(
        "Demonstrates 4 Tasker workflow orchestration patterns: "
        "e-commerce order processing, data pipeline analytics, "
        "microservices user registration, and team scaling with "
        "namespace isolation."
    ),
    version="0.1.0",
    lifespan=lifespan,
)

app.include_router(orders.router, prefix="/orders", tags=["E-commerce Orders"])
app.include_router(analytics.router, prefix="/analytics", tags=["Data Pipeline"])
app.include_router(services.router, prefix="/services", tags=["Microservices"])
app.include_router(compliance.router, prefix="/compliance", tags=["Team Scaling"])


@app.get("/health")
async def health_check() -> dict:
    """Application health check endpoint."""
    from tasker_core import is_worker_running

    return {
        "status": "healthy" if is_worker_running() else "degraded",
        "worker_running": is_worker_running(),
    }
