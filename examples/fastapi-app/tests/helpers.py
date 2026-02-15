"""Polling helpers for verifying Tasker task completion via the orchestration API.

Usage:
    from tests.helpers import wait_for_task_completion, get_task, get_task_steps

    task = await wait_for_task_completion(task_uuid)
    assert task["status"] == "complete"
"""

from __future__ import annotations

import asyncio
import os
import time

import httpx

ORCHESTRATION_URL = os.environ.get("ORCHESTRATION_URL", "http://localhost:8080")
API_KEY = os.environ.get("TASKER_API_KEY", "test-api-key-full-access")
DEFAULT_TIMEOUT = 30
POLL_INTERVAL = 1

# Truly terminal: no further progress possible.
TERMINAL_STATUSES = {"complete", "error", "cancelled"}

# Also terminal but may appear before retries finish — give a grace period.
FAILURE_STATUSES = {"blocked_by_failures"}


async def wait_for_task_completion(
    task_uuid: str,
    *,
    timeout: int = DEFAULT_TIMEOUT,
    poll_interval: float = POLL_INTERVAL,
) -> dict:
    """Poll GET /v1/tasks/{uuid} until the task reaches a terminal status.

    A task in ``blocked_by_failures`` is given a 10-second grace period before
    being treated as terminal, since steps may still be in waiting_for_retry.

    Args:
        task_uuid: The task UUID to poll.
        timeout: Maximum seconds to wait (default 30).
        poll_interval: Seconds between polls (default 1).

    Returns:
        The task response dict.

    Raises:
        TimeoutError: If the task does not finish within the timeout.
    """
    deadline = time.monotonic() + timeout
    failure_seen_at: float | None = None

    async with httpx.AsyncClient(base_url=ORCHESTRATION_URL) as client:
        while True:
            task = await get_task(task_uuid, client=client)
            status = task["status"]

            # Immediately terminal
            if status in TERMINAL_STATUSES:
                return task

            # Failure status with grace period
            if status in FAILURE_STATUSES:
                if failure_seen_at is None:
                    failure_seen_at = time.monotonic()
                if time.monotonic() - failure_seen_at >= 10:
                    return task
            else:
                failure_seen_at = None

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(
                    f"Task {task_uuid} did not complete within {timeout}s. "
                    f"Last status: {status}, "
                    f"completion: {task.get('completion_percentage', '?')}%"
                )

            await asyncio.sleep(min(poll_interval, remaining))


async def get_task(task_uuid: str, *, client: httpx.AsyncClient | None = None) -> dict:
    """Fetch a single task from the orchestration API.

    Args:
        task_uuid: The task UUID.
        client: Optional reusable httpx client.

    Returns:
        Parsed JSON response dict.
    """
    headers = {"X-API-Key": API_KEY}

    if client is not None:
        resp = await client.get(f"/v1/tasks/{task_uuid}", headers=headers)
    else:
        async with httpx.AsyncClient(base_url=ORCHESTRATION_URL) as c:
            resp = await c.get(f"/v1/tasks/{task_uuid}", headers=headers)

    resp.raise_for_status()
    return resp.json()


async def get_task_steps(task_uuid: str) -> list[dict]:
    """Return the steps array from a task.

    Args:
        task_uuid: The task UUID.

    Returns:
        List of step dicts.
    """
    task = await get_task(task_uuid)
    return task.get("steps", [])


async def find_step(task_uuid: str, step_name: str) -> dict | None:
    """Find a specific step by name within a task.

    Args:
        task_uuid: The task UUID.
        step_name: The step name to find.

    Returns:
        The step dict, or None if not found.
    """
    steps = await get_task_steps(task_uuid)
    return next((s for s in steps if s["name"] == step_name), None)
