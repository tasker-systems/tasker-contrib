"""Customer Success namespace step handlers for refund processing.

5 sequential steps owned by the Customer Success team:
  ValidateRefundRequest -> CheckRefundPolicy -> ApproveRefund
      -> ExecuteRefund -> UpdateTicket

This demonstrates the team-scaling pattern where each namespace has its
own handler implementations. The CustomerSuccess team owns the validation,
policy checking, and ticket management, while delegating the actual
financial operations to the Payments namespace.
"""

from __future__ import annotations

import hashlib
import uuid
from datetime import datetime, timezone
from typing import Any

from tasker_core import ErrorType, StepContext, StepHandler, StepHandlerResult


class ValidateRefundRequestHandler(StepHandler):
    """Validate that the refund request is well-formed and eligible.

    Checks order reference, amount, reason, and customer information.
    Applies basic business rules to determine initial eligibility.
    """

    handler_name = "validate_refund_request"
    handler_version = "1.0.0"

    VALID_REASONS = {
        "customer_request",
        "defective_product",
        "wrong_item",
        "late_delivery",
        "duplicate_charge",
        "service_issue",
    }

    MAX_REFUND_AMOUNT = 10000.00

    def call(self, context: StepContext) -> StepHandlerResult:
        # Source-aligned: read ticket_id, customer_id, refund_amount, refund_reason
        ticket_id = context.get_input("ticket_id")
        customer_id = context.get_input("customer_id")
        refund_amount = context.get_input("refund_amount")
        refund_reason = context.get_input("refund_reason")

        # Map to local variables for validation logic
        order_ref = ticket_id  # Use ticket_id as order reference
        amount = refund_amount
        reason = refund_reason
        customer_email = context.get_input("customer_email")

        if not ticket_id:
            return StepHandlerResult.failure(
                message=f"Invalid ticket_id: {ticket_id}",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="INVALID_ORDER_REF",
            )

        if not amount or amount <= 0:
            return StepHandlerResult.failure(
                message=f"Refund amount must be positive, got: {amount}",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="INVALID_AMOUNT",
            )

        if amount > self.MAX_REFUND_AMOUNT:
            return StepHandlerResult.failure(
                message=f"Refund amount ${amount:.2f} exceeds maximum ${self.MAX_REFUND_AMOUNT:.2f}",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="AMOUNT_EXCEEDS_MAX",
            )

        if reason and reason not in self.VALID_REASONS:
            return StepHandlerResult.failure(
                message=f"Invalid refund reason: {reason}. Valid: {', '.join(sorted(self.VALID_REASONS))}",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="INVALID_REASON",
            )

        request_id = f"ref_{uuid.uuid4().hex[:12]}"
        validation_hash = hashlib.sha256(
            f"{order_ref}:{amount}:{reason}:{customer_email}".encode()
        ).hexdigest()[:16]
        payment_id = f"pay_{uuid.uuid4().hex[:12]}"

        # Determine customer tier based on customer_id
        customer_tier = "standard"
        if customer_id:
            cid = customer_id.lower()
            if "vip" in cid or "premium" in cid:
                customer_tier = "premium"
            elif "gold" in cid:
                customer_tier = "gold"

        from datetime import timedelta

        original_purchase_date = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
        now = datetime.now(timezone.utc).isoformat()

        return StepHandlerResult.success(
            result={
                "request_validated": True,
                "ticket_id": ticket_id,
                "customer_id": customer_id,
                "ticket_status": "open",
                "customer_tier": customer_tier,
                "original_purchase_date": original_purchase_date,
                "payment_id": payment_id,
                "validation_timestamp": now,
                "namespace": "customer_success",
                "request_id": request_id,
                "order_ref": order_ref,
                "amount": amount,
                "reason": reason or "customer_request",
                "customer_email": customer_email,
                "validation_hash": validation_hash,
                "eligible": True,
                "validated_at": now,
            },
            metadata={"reason_category": reason or "customer_request"},
        )


class CheckRefundPolicyHandler(StepHandler):
    """Check the refund request against company refund policies.

    Applies policy rules based on refund reason, amount thresholds,
    and customer history. Determines if auto-approval is possible or
    if manual review is required.
    """

    handler_name = "check_refund_policy"
    handler_version = "1.0.0"

    AUTO_APPROVE_THRESHOLD = 50.00
    REVIEW_THRESHOLD = 500.00
    MAX_REFUND_AMOUNT = 10000.00

    def call(self, context: StepContext) -> StepHandlerResult:
        validation = context.get_dependency_result("validate_refund_request")
        if validation is None or not validation.get("request_validated"):
            return StepHandlerResult.failure(
                message="Missing validate_refund_request dependency",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        # Source-aligned: read from dependency fields
        customer_tier = context.get_dependency_field("validate_refund_request", "customer_tier") or "standard"
        original_purchase_date = context.get_dependency_field("validate_refund_request", "original_purchase_date")

        # Source-aligned: read from task context
        refund_amount = context.get_input("refund_amount")
        _refund_reason = context.get_input("refund_reason")

        amount = refund_amount or validation.get("amount", 0.0)
        reason = validation.get("reason", "customer_request")
        request_id = validation.get("request_id")

        # Determine approval path
        auto_approve_reasons = {"defective_product", "wrong_item", "duplicate_charge"}

        if amount <= self.AUTO_APPROVE_THRESHOLD:
            approval_path = "auto_approved"
            requires_approval = False
        elif reason in auto_approve_reasons and amount <= self.REVIEW_THRESHOLD:
            approval_path = "auto_approved"
            requires_approval = False
        elif amount > self.REVIEW_THRESHOLD:
            approval_path = "manager_review"
            requires_approval = True
        else:
            approval_path = "standard_review"
            requires_approval = True

        policy_id = f"pol_{uuid.uuid4().hex[:10]}"
        now = datetime.now(timezone.utc).isoformat()

        # Compute days since purchase if available
        days_since_purchase = 30  # default
        refund_window_days = 90
        if original_purchase_date:
            try:
                purchase_date = datetime.fromisoformat(original_purchase_date.replace("Z", "+00:00"))
                days_since_purchase = (datetime.now(timezone.utc) - purchase_date).days
            except (ValueError, TypeError):
                pass

        return StepHandlerResult.success(
            result={
                "policy_checked": True,
                "policy_compliant": True,
                "customer_tier": customer_tier,
                "refund_window_days": refund_window_days,
                "days_since_purchase": days_since_purchase,
                "within_refund_window": days_since_purchase <= refund_window_days,
                "requires_approval": requires_approval,
                "max_allowed_amount": self.MAX_REFUND_AMOUNT,
                "policy_checked_at": now,
                "namespace": "customer_success",
                "policy_id": policy_id,
                "request_id": request_id,
                "approval_path": approval_path,
                "requires_review": requires_approval,
                "amount_tier": (
                    "small" if amount <= self.AUTO_APPROVE_THRESHOLD
                    else "medium" if amount <= self.REVIEW_THRESHOLD
                    else "large"
                ),
                "policy_version": "2026.1",
                "rules_applied": [
                    f"amount_threshold_{self.AUTO_APPROVE_THRESHOLD}",
                    f"reason_category_{reason}",
                    f"review_threshold_{self.REVIEW_THRESHOLD}",
                ],
                "checked_at": now,
            },
        )


class ApproveRefundHandler(StepHandler):
    """Approve the refund based on policy check results.

    For auto-approved refunds, generates approval immediately.
    For review-required refunds, simulates manager approval.
    """

    handler_name = "get_manager_approval"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        policy = context.get_dependency_result("check_refund_policy")

        if not policy or not policy.get("policy_checked"):
            return StepHandlerResult.failure(
                message="Missing check_refund_policy dependency",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        # Source-aligned: read from dependency fields
        requires_approval = context.get_dependency_field("check_refund_policy", "requires_approval")
        customer_tier = context.get_dependency_field("check_refund_policy", "customer_tier")
        ticket_id = context.get_dependency_field("validate_refund_request", "ticket_id")
        customer_id = context.get_dependency_field("validate_refund_request", "customer_id")

        # Source-aligned: read from task context
        refund_amount = context.get_input("refund_amount")
        refund_reason = context.get_input("refund_reason")

        validation = context.get_dependency_result("validate_refund_request")
        request_id = (validation or {}).get("request_id")
        amount = refund_amount or (validation or {}).get("amount", 0.0)
        approval_path = policy.get("approval_path", "standard_review")

        approval_id = f"apr_{uuid.uuid4().hex[:12]}"
        now = datetime.now(timezone.utc).isoformat()

        if requires_approval:
            manager_id = f"mgr_{(hash(ticket_id or '') % 5) + 1}"
            manager_notes = f"Manager-approved refund of ${amount:.2f} for customer {customer_id}"

            return StepHandlerResult.success(
                result={
                    "approval_obtained": True,
                    "approval_required": True,
                    "auto_approved": False,
                    "approval_id": approval_id,
                    "manager_id": manager_id,
                    "manager_notes": manager_notes,
                    "approved_at": now,
                    "namespace": "customer_success",
                    "request_id": request_id,
                    "approved": True,
                    "approver": manager_id,
                    "approval_path": approval_path,
                    "approval_note": manager_notes,
                    "amount_approved": amount,
                },
                metadata={"approval_path": approval_path},
            )
        else:
            return StepHandlerResult.success(
                result={
                    "approval_obtained": True,
                    "approval_required": False,
                    "auto_approved": True,
                    "approval_id": None,
                    "manager_id": None,
                    "manager_notes": f"Auto-approved for customer tier {customer_tier}",
                    "approved_at": now,
                    "namespace": "customer_success",
                    "request_id": request_id,
                    "approved": True,
                    "approver": "system",
                    "approval_path": approval_path,
                    "approval_note": "Auto-approved per refund policy",
                    "amount_approved": amount,
                },
                metadata={"approval_path": approval_path},
            )


class ExecuteRefundHandler(StepHandler):
    """Execute the approved refund by initiating the financial transaction.

    This step bridges between the CustomerSuccess and Payments namespaces.
    In a real system, this might delegate to the Payments team's API.
    Here we simulate the refund execution.
    """

    handler_name = "execute_refund_workflow"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        approval = context.get_dependency_result("get_manager_approval")

        if not approval or not approval.get("approval_obtained"):
            return StepHandlerResult.failure(
                message="Refund was not approved",
                error_type=ErrorType.PERMANENT_ERROR,
                retryable=False,
                error_code="NOT_APPROVED",
            )

        # Source-aligned: read from dependency fields
        payment_id = context.get_dependency_field("validate_refund_request", "payment_id")
        approval_id = context.get_dependency_field("get_manager_approval", "approval_id")

        # Source-aligned: read from task context
        refund_amount = context.get_input("refund_amount")
        refund_reason = context.get_input("refund_reason") or "customer_request"
        customer_email = context.get_input("customer_email") or "customer@example.com"
        ticket_id = context.get_input("ticket_id")
        correlation_id = context.get_input("correlation_id") or f"cs-{uuid.uuid4().hex[:16]}"

        validation = context.get_dependency_result("validate_refund_request")
        amount = refund_amount or approval.get("amount_approved", 0.0)
        request_id = (validation or {}).get("request_id")
        order_ref = (validation or {}).get("order_ref")

        delegated_task_id = f"task_{uuid.uuid4()}"
        refund_id = f"rfnd_{uuid.uuid4().hex[:12]}"
        transaction_ref = f"txn_{uuid.uuid4().hex[:16]}"
        now = datetime.now(timezone.utc).isoformat()

        return StepHandlerResult.success(
            result={
                "task_delegated": True,
                "target_namespace": "payments",
                "target_workflow": "process_refund",
                "delegated_task_id": delegated_task_id,
                "delegated_task_status": "created",
                "delegation_timestamp": now,
                "correlation_id": correlation_id,
                "namespace": "customer_success",
                "refund_id": refund_id,
                "transaction_ref": transaction_ref,
                "request_id": request_id,
                "order_ref": order_ref,
                "amount_refunded": amount,
                "currency": "USD",
                "refund_method": "original_payment_method",
                "estimated_arrival": "3-5 business days",
                "status": "processed",
                "executed_at": now,
            },
            metadata={"gateway": "simulated"},
        )


class UpdateTicketHandler(StepHandler):
    """Update the customer support ticket with refund outcome.

    Creates a resolution summary on the support ticket, including
    all relevant reference IDs for audit trail.
    """

    handler_name = "update_ticket_status"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        delegation_result = context.get_dependency_result("execute_refund_workflow")

        if not delegation_result or not delegation_result.get("task_delegated"):
            return StepHandlerResult.failure(
                message="Missing upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        # Source-aligned: read from dependency fields
        ticket_id = context.get_dependency_field("validate_refund_request", "ticket_id")
        customer_id = context.get_dependency_field("validate_refund_request", "customer_id")
        delegated_task_id = context.get_dependency_field("execute_refund_workflow", "delegated_task_id")
        correlation_id = context.get_dependency_field("execute_refund_workflow", "correlation_id")

        # Source-aligned: read from task context
        refund_amount = context.get_input("refund_amount")
        _refund_reason = context.get_input("refund_reason")

        validation = context.get_dependency_result("validate_refund_request")
        request_id = (validation or {}).get("request_id")
        customer_email = (validation or {}).get("customer_email")
        refund_id = delegation_result.get("refund_id")
        amount = refund_amount or delegation_result.get("amount_refunded", 0.0)
        order_ref = (validation or {}).get("order_ref")

        now = datetime.now(timezone.utc).isoformat()

        resolution_note = (
            f"Refund of ${amount:.2f} processed for order {order_ref}. "
            f"Refund ID: {refund_id}. Customer notified at {customer_email}. "
            f"Delegated task ID: {delegated_task_id}. "
            f"Correlation ID: {correlation_id}. "
            f"Estimated arrival: 3-5 business days."
        )

        return StepHandlerResult.success(
            result={
                "ticket_updated": True,
                "ticket_id": ticket_id or f"tkt_{uuid.uuid4().hex[:12]}",
                "previous_status": "in_progress",
                "new_status": "resolved",
                "resolution_note": resolution_note,
                "updated_at": now,
                "refund_completed": True,
                "delegated_task_id": delegated_task_id,
                "namespace": "customer_success",
                "request_id": request_id,
                "resolution": "refund_completed",
                "customer_notified": True,
                "notification_channel": "email",
                "refund_id": refund_id,
                "amount_refunded": amount,
                "ticket_status": "resolved",
                "resolved_at": now,
            },
            metadata={"resolution_type": "refund"},
        )
