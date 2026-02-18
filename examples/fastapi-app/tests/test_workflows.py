"""Integration tests for the 4 Tasker workflow patterns.

Each test creates a domain record via the HTTP API and verifies the response
structure. When a tasker orchestration server is running, the tests also
verify that task_uuid is populated and the task status endpoint returns data.

Run with: pytest tests/ -v
"""

from __future__ import annotations

import pytest
from httpx import AsyncClient


class TestEcommerceOrderWorkflow:
    """Test the e-commerce order processing workflow (5 sequential steps)."""

    @pytest.mark.asyncio
    async def test_create_order(self, client: AsyncClient) -> None:
        """POST /orders/ creates an order and returns task_uuid."""
        response = await client.post(
            "/orders/",
            json={
                "customer_email": "test@example.com",
                "items": [
                    {
                        "sku": "WIDGET-001",
                        "name": "Premium Widget",
                        "quantity": 2,
                        "unit_price": 29.99,
                    },
                    {
                        "sku": "GADGET-002",
                        "name": "Deluxe Gadget",
                        "quantity": 1,
                        "unit_price": 149.99,
                    },
                ],
                "payment_token": "tok_test_success",
                "shipping_address": "456 Elm St, Springfield, US 62704",
            },
        )

        assert response.status_code == 201
        data = response.json()
        assert data["customer_email"] == "test@example.com"
        assert len(data["items"]) == 2
        assert data["status"] in ("pending", "processing", "task_creation_failed")
        assert "id" in data
        assert "created_at" in data

    @pytest.mark.asyncio
    async def test_get_order(self, client: AsyncClient) -> None:
        """POST then GET /orders/{id} returns order with status."""
        create_response = await client.post(
            "/orders/",
            json={
                "customer_email": "get-test@example.com",
                "items": [
                    {
                        "sku": "ITEM-100",
                        "name": "Test Item",
                        "quantity": 1,
                        "unit_price": 10.00,
                    },
                ],
            },
        )
        assert create_response.status_code == 201
        order_id = create_response.json()["id"]

        get_response = await client.get(f"/orders/{order_id}")
        assert get_response.status_code == 200
        data = get_response.json()
        assert data["id"] == order_id
        assert data["customer_email"] == "get-test@example.com"

    @pytest.mark.asyncio
    async def test_get_nonexistent_order(self, client: AsyncClient) -> None:
        """GET /orders/999999 returns 404."""
        response = await client.get("/orders/999999")
        assert response.status_code == 404


class TestDataPipelineWorkflow:
    """Test the data pipeline analytics workflow (8-step DAG)."""

    @pytest.mark.asyncio
    async def test_create_analytics_job(self, client: AsyncClient) -> None:
        """POST /analytics/jobs/ creates a job and returns task_uuid."""
        response = await client.post(
            "/analytics/jobs/",
            json={
                "source": "web_traffic",
                "dataset_url": "s3://data-bucket/traffic-2026-01.parquet",
                "date_range_start": "2026-01-01",
                "date_range_end": "2026-01-31",
                "granularity": "daily",
            },
        )

        assert response.status_code == 201
        data = response.json()
        assert data["source"] == "web_traffic"
        assert data["status"] in ("pending", "processing", "task_creation_failed")
        assert "id" in data

    @pytest.mark.asyncio
    async def test_get_analytics_job(self, client: AsyncClient) -> None:
        """POST then GET /analytics/jobs/{id} returns job with status."""
        create_response = await client.post(
            "/analytics/jobs/",
            json={
                "source": "sales",
                "date_range_start": "2026-01-01",
                "date_range_end": "2026-01-31",
            },
        )
        assert create_response.status_code == 201
        job_id = create_response.json()["id"]

        get_response = await client.get(f"/analytics/jobs/{job_id}")
        assert get_response.status_code == 200
        data = get_response.json()
        assert data["id"] == job_id
        assert data["source"] == "sales"

    @pytest.mark.asyncio
    async def test_get_nonexistent_job(self, client: AsyncClient) -> None:
        """GET /analytics/jobs/999999 returns 404."""
        response = await client.get("/analytics/jobs/999999")
        assert response.status_code == 404


class TestMicroservicesWorkflow:
    """Test the microservices user registration workflow (5-step diamond)."""

    @pytest.mark.asyncio
    async def test_create_service_request(self, client: AsyncClient) -> None:
        """POST /services/requests/ creates a request and returns task_uuid."""
        response = await client.post(
            "/services/requests/",
            json={
                "user_id": "usr_test_001",
                "request_type": "user_registration",
                "email": "newuser@example.com",
                "full_name": "Jane Doe",
                "plan": "professional",
            },
        )

        assert response.status_code == 201
        data = response.json()
        assert data["user_id"] == "usr_test_001"
        assert data["request_type"] == "user_registration"
        assert data["status"] in ("pending", "processing", "task_creation_failed")
        assert "id" in data

    @pytest.mark.asyncio
    async def test_get_service_request(self, client: AsyncClient) -> None:
        """POST then GET /services/requests/{id} returns request with status."""
        create_response = await client.post(
            "/services/requests/",
            json={
                "user_id": "usr_test_002",
                "email": "another@example.com",
                "full_name": "John Smith",
                "plan": "starter",
            },
        )
        assert create_response.status_code == 201
        request_id = create_response.json()["id"]

        get_response = await client.get(f"/services/requests/{request_id}")
        assert get_response.status_code == 200
        data = get_response.json()
        assert data["id"] == request_id
        assert data["user_id"] == "usr_test_002"

    @pytest.mark.asyncio
    async def test_get_nonexistent_request(self, client: AsyncClient) -> None:
        """GET /services/requests/999999 returns 404."""
        response = await client.get("/services/requests/999999")
        assert response.status_code == 404


class TestTeamScalingWorkflow:
    """Test the team scaling workflow with namespace isolation (2 namespaces, 9 steps)."""

    @pytest.mark.asyncio
    async def test_create_customer_success_check(self, client: AsyncClient) -> None:
        """POST /compliance/checks/ with customer_success_py namespace."""
        response = await client.post(
            "/compliance/checks/",
            json={
                "order_ref": "ORD-ABC123",
                "namespace": "customer_success_py",
                "reason": "defective_product",
                "amount": 75.50,
                "customer_email": "refund@example.com",
            },
        )

        assert response.status_code == 201
        data = response.json()
        assert data["order_ref"] == "ORD-ABC123"
        assert data["namespace"] == "customer_success_py"
        assert data["status"] in ("pending", "processing", "task_creation_failed")
        assert "id" in data

    @pytest.mark.asyncio
    async def test_create_payments_check(self, client: AsyncClient) -> None:
        """POST /compliance/checks/ with payments_py namespace."""
        response = await client.post(
            "/compliance/checks/",
            json={
                "order_ref": "ORD-XYZ789",
                "namespace": "payments_py",
                "reason": "duplicate_charge",
                "amount": 199.99,
                "customer_email": "billing@example.com",
            },
        )

        assert response.status_code == 201
        data = response.json()
        assert data["order_ref"] == "ORD-XYZ789"
        assert data["namespace"] == "payments_py"
        assert data["status"] in ("pending", "processing", "task_creation_failed")

    @pytest.mark.asyncio
    async def test_invalid_namespace(self, client: AsyncClient) -> None:
        """POST /compliance/checks/ with invalid namespace returns 400."""
        response = await client.post(
            "/compliance/checks/",
            json={
                "order_ref": "ORD-BAD",
                "namespace": "invalid_namespace",
                "reason": "customer_request",
                "amount": 10.00,
                "customer_email": "test@example.com",
            },
        )
        assert response.status_code == 400

    @pytest.mark.asyncio
    async def test_get_compliance_check(self, client: AsyncClient) -> None:
        """POST then GET /compliance/checks/{id} returns check with status."""
        create_response = await client.post(
            "/compliance/checks/",
            json={
                "order_ref": "ORD-GET-TEST",
                "namespace": "customer_success_py",
                "reason": "customer_request",
                "amount": 25.00,
                "customer_email": "gettest@example.com",
            },
        )
        assert create_response.status_code == 201
        check_id = create_response.json()["id"]

        get_response = await client.get(f"/compliance/checks/{check_id}")
        assert get_response.status_code == 200
        data = get_response.json()
        assert data["id"] == check_id
        assert data["order_ref"] == "ORD-GET-TEST"

    @pytest.mark.asyncio
    async def test_get_nonexistent_check(self, client: AsyncClient) -> None:
        """GET /compliance/checks/999999 returns 404."""
        response = await client.get("/compliance/checks/999999")
        assert response.status_code == 404


class TestHealthEndpoint:
    """Test the application health check endpoint."""

    @pytest.mark.asyncio
    async def test_health_check(self, client: AsyncClient) -> None:
        """GET /health returns worker status."""
        response = await client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert "worker_running" in data


@pytest.mark.completion
class TestTaskCompletionVerification:
    """Verify end-to-end task dispatch through the orchestration loop.

    These tests create tasks via app endpoints, poll the orchestration API,
    and confirm steps were dispatched and processed. Tasks reach a terminal
    status (complete or blocked_by_failures) which proves the infrastructure
    loop works.

    Run with: pytest tests/ -v -m completion
    """

    @pytest.mark.asyncio
    async def test_ecommerce_order_dispatches_and_processes(
        self, client: AsyncClient
    ) -> None:
        """E-commerce order: task created, steps dispatched, reaches terminal status."""
        from tests.helpers import wait_for_task_completion

        response = await client.post(
            "/orders/",
            json={
                "customer_email": "completion-test@example.com",
                "items": [
                    {
                        "sku": "COMPLETION-001",
                        "name": "Completion Widget",
                        "quantity": 1,
                        "unit_price": 19.99,
                    }
                ],
                "payment_token": "tok_test_completion",
                "shipping_address": "1 Test Ln, Testville, US 97201",
            },
        )

        assert response.status_code == 201
        data = response.json()
        task_uuid = data.get("task_uuid")
        assert task_uuid, "Expected task_uuid in response"

        task = await wait_for_task_completion(task_uuid)

        # Task must fully complete (all steps successful)
        assert task["status"] == "complete", f"Expected task to complete, got: {task['status']}"
        assert task["total_steps"] == 5

        # All steps must have reached "complete" state
        steps = task["steps"]
        assert len(steps) == 5
        completed = sum(1 for s in steps if s["current_state"] == "complete")
        assert completed == 5, f"Expected all 5 steps to complete, got {completed}"

        # Handler dispatch works: first step was attempted
        validate_step = next(
            (s for s in steps if s["name"] == "validate_cart"), None
        )
        assert validate_step is not None
        assert validate_step["attempts"] >= 1

        print(f"  E-commerce task: {task['status']} ({completed}/5 steps complete)")

    @pytest.mark.asyncio
    async def test_analytics_pipeline_dispatches_and_processes(
        self, client: AsyncClient
    ) -> None:
        """Analytics pipeline: parallel branches dispatched, reaches terminal status."""
        from tests.helpers import wait_for_task_completion

        response = await client.post(
            "/analytics/jobs/",
            json={
                "source": "web_traffic",
                "date_range_start": "2026-01-01",
                "date_range_end": "2026-01-07",
                "granularity": "daily",
            },
        )

        assert response.status_code == 201
        data = response.json()
        task_uuid = data.get("task_uuid")
        assert task_uuid, "Expected task_uuid in response"

        task = await wait_for_task_completion(task_uuid)

        assert task["status"] == "complete", f"Expected task to complete, got: {task['status']}"
        assert task["total_steps"] == 8

        steps = task["steps"]
        step_names = {s["name"] for s in steps}

        # Verify the 3 parallel extract steps exist
        for name in (
            "extract_sales_data",
            "extract_inventory_data",
            "extract_customer_data",
        ):
            assert name in step_names, f"Expected step '{name}' to be present"

        # At least one extract step was attempted (parallel dispatch works)
        extract_steps = [s for s in steps if s["name"].startswith("extract_")]
        attempted = sum(1 for s in extract_steps if s["attempts"] > 0)
        assert attempted >= 1, "Expected at least one extract step to be attempted"

        # All steps must have reached "complete" state
        completed = sum(1 for s in steps if s["current_state"] == "complete")
        assert completed == 8, f"Expected all 8 steps to complete, got {completed}"

        print(f"  Analytics task: {task['status']} ({completed}/8 steps complete)")

    @pytest.mark.asyncio
    async def test_user_registration_dispatches_and_processes(
        self, client: AsyncClient
    ) -> None:
        """User registration: diamond dependency pattern dispatched, reaches terminal status."""
        from tests.helpers import wait_for_task_completion

        response = await client.post(
            "/services/requests/",
            json={
                "user_id": "completion_user_001",
                "email": "completion-reg@example.com",
                "full_name": "Completion Tester",
                "plan": "professional",
            },
        )

        assert response.status_code == 201
        data = response.json()
        task_uuid = data.get("task_uuid")
        assert task_uuid, "Expected task_uuid in response"

        task = await wait_for_task_completion(task_uuid)

        assert task["status"] == "complete", f"Expected task to complete, got: {task['status']}"
        assert task["total_steps"] == 5

        steps = task["steps"]
        step_names = {s["name"] for s in steps}
        for name in (
            "create_user_account",
            "setup_billing_profile",
            "initialize_preferences",
            "send_welcome_sequence",
            "update_user_status",
        ):
            assert name in step_names, f"Expected step '{name}' to be present"

        # All steps must have reached "complete" state
        completed = sum(1 for s in steps if s["current_state"] == "complete")
        assert completed == 5, f"Expected all 5 steps to complete, got {completed}"

        print(f"  User registration task: {task['status']} ({completed}/5 steps complete)")

    @pytest.mark.asyncio
    async def test_customer_success_refund_dispatches_and_processes(
        self, client: AsyncClient
    ) -> None:
        """Customer success refund: task dispatched, reaches terminal status."""
        from tests.helpers import wait_for_task_completion

        response = await client.post(
            "/compliance/checks/",
            json={
                "order_ref": "ORD-COMP-CS-001",
                "namespace": "customer_success_py",
                "reason": "defective_product",
                "amount": 99.99,
                "customer_email": "cs-completion@example.com",
            },
        )

        assert response.status_code == 201
        data = response.json()
        task_uuid = data.get("task_uuid")
        assert task_uuid, "Expected task_uuid in response"

        task = await wait_for_task_completion(task_uuid)

        assert task["status"] == "complete", f"Expected task to complete, got: {task['status']}"
        assert task["total_steps"] == 5

        # All steps must have reached "complete" state
        completed = sum(1 for s in task["steps"] if s["current_state"] == "complete")
        assert completed == 5, f"Expected all 5 steps to complete, got {completed}"

        print(f"  Customer success refund task: {task['status']} ({completed}/5 steps complete)")

    @pytest.mark.asyncio
    async def test_payments_refund_dispatches_and_processes(
        self, client: AsyncClient
    ) -> None:
        """Payments refund: task dispatched, reaches terminal status."""
        from tests.helpers import wait_for_task_completion

        response = await client.post(
            "/compliance/checks/",
            json={
                "order_ref": "ORD-COMP-PAY-001",
                "namespace": "payments_py",
                "reason": "duplicate_charge",
                "amount": 50.00,
                "customer_email": "pay-completion@example.com",
            },
        )

        assert response.status_code == 201
        data = response.json()
        task_uuid = data.get("task_uuid")
        assert task_uuid, "Expected task_uuid in response"

        task = await wait_for_task_completion(task_uuid)

        assert task["status"] == "complete", f"Expected task to complete, got: {task['status']}"
        assert task["total_steps"] == 4

        # All steps must have reached "complete" state
        completed = sum(1 for s in task["steps"] if s["current_state"] == "complete")
        assert completed == 4, f"Expected all 4 steps to complete, got {completed}"

        print(f"  Payments refund task: {task['status']} ({completed}/4 steps complete)")
