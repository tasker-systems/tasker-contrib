"""Async database session configuration for the FastAPI example app.

Uses SQLAlchemy 2.0 async engine with asyncpg driver. The app-specific
database (APP_DATABASE_URL) is separate from tasker's internal database.
"""

from __future__ import annotations

import os
from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

APP_DATABASE_URL = os.environ.get(
    "APP_DATABASE_URL",
    "postgresql://tasker:tasker@localhost:5432/example_fastapi",
)

# Convert postgresql:// to postgresql+asyncpg:// for async driver
async_url = APP_DATABASE_URL.replace("postgresql://", "postgresql+asyncpg://", 1)

engine = create_async_engine(
    async_url,
    echo=False,
    pool_size=10,
    max_overflow=5,
    pool_pre_ping=True,
)

async_session_factory = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency that provides an async database session.

    Yields:
        AsyncSession bound to the app-specific database.
    """
    async with async_session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
