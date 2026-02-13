"""Pytest fixtures for the FastAPI example application tests.

Provides:
- tasker_worker: Session-scoped fixture that bootstraps the tasker worker
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
    """Bootstrap the tasker worker for the entire test session.

    Starts the worker system (which initializes the orchestration client)
    and stops it after all tests complete.
    """
    from tasker_core import bootstrap_worker, stop_worker

    result = bootstrap_worker()
    assert result.status == "started", f"Worker bootstrap failed: {result}"

    yield result

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
