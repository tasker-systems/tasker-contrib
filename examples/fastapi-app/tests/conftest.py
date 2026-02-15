"""Pytest fixtures for the FastAPI example application tests.

Provides:
- tasker_worker: Session-scoped fixture that bootstraps the tasker worker
  and starts the event processing pipeline
- client: Async HTTP client for testing FastAPI endpoints
- db_session: Async database session for direct DB assertions
"""

from __future__ import annotations

from collections.abc import AsyncGenerator
from typing import Any

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session_factory


@pytest.fixture(scope="session")
def tasker_worker() -> Any:
    """Bootstrap the tasker worker and event processing for the test session.

    Sets up the full pipeline:
    1. Bootstrap the Rust worker (database, messaging, orchestration client)
    2. Discover step handlers from app.handlers package
    3. Start EventBridge, StepExecutionSubscriber, and EventPoller

    Stops everything after all tests complete.
    """
    from tasker_core import (
        EventBridge,
        EventPoller,
        HandlerRegistry,
        StepExecutionSubscriber,
        bootstrap_worker,
        stop_worker,
    )

    # 1. Bootstrap the Rust worker system
    result = bootstrap_worker()
    assert result.status == "started", f"Worker bootstrap failed: {result}"

    # 2. Discover step handlers
    registry = HandlerRegistry.instance()
    count = registry.discover_handlers("app.handlers")
    assert count > 0, "No step handlers discovered"

    # 3. Start event processing pipeline
    bridge = EventBridge.instance()
    bridge.start()

    subscriber = StepExecutionSubscriber(
        event_bridge=bridge,
        handler_registry=registry,
        worker_id=result.worker_id,
    )
    subscriber.start()

    poller = EventPoller()
    poller.on_step_event(lambda event: bridge.publish("step.execution.received", event))
    poller.start()

    yield result

    # Shutdown
    poller.stop()
    subscriber.stop()
    bridge.stop()
    stop_worker()


@pytest_asyncio.fixture
async def client(tasker_worker: Any) -> AsyncGenerator[AsyncClient, None]:
    """Provide an async HTTP client bound to the FastAPI test app.

    The tasker_worker fixture is injected to ensure the worker is running
    before any HTTP requests are made.
    """
    from app.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest_asyncio.fixture
async def db_session() -> AsyncGenerator[AsyncSession, None]:
    """Provide a clean async database session for test assertions."""
    async with async_session_factory() as session:
        yield session
