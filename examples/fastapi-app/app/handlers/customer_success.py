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

    handler_name = "cs_validate_refund_request"
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
        order_ref = context.get_input("order_ref")
        amount = context.get_input("amount")
        reason = context.get_input("reason")
        customer_email = context.get_input("customer_email")

        if not order_ref or len(order_ref) < 3:
            return StepHandlerResult.failure(
                message=f"Invalid order reference: {order_ref}",
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

        return StepHandlerResult.success(
            result={
                "request_id": request_id,
                "order_ref": order_ref,
                "amount": amount,
                "reason": reason or "customer_request",
                "customer_email": customer_email,
                "validation_hash": validation_hash,
                "eligible": True,
                "validated_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"reason_category": reason or "customer_request"},
        )


class CheckRefundPolicyHandler(StepHandler):
    """Check the refund request against company refund policies.

    Applies policy rules based on refund reason, amount thresholds,
    and customer history. Determines if auto-approval is possible or
    if manual review is required.
    """

    handler_name = "cs_check_refund_policy"
    handler_version = "1.0.0"

    AUTO_APPROVE_THRESHOLD = 50.00
    REVIEW_THRESHOLD = 500.00

    def call(self, context: StepContext) -> StepHandlerResult:
        validation = context.get_dependency_result("cs_validate_refund_request")
        if validation is None:
            return StepHandlerResult.failure(
                message="Missing cs_validate_refund_request dependency",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        amount = validation.get("amount", 0.0)
        reason = validation.get("reason", "customer_request")
        request_id = validation.get("request_id")

        # Determine approval path
        auto_approve_reasons = {"defective_product", "wrong_item", "duplicate_charge"}

        if amount <= self.AUTO_APPROVE_THRESHOLD:
            approval_path = "auto_approved"
            requires_review = False
        elif reason in auto_approve_reasons and amount <= self.REVIEW_THRESHOLD:
            approval_path = "auto_approved"
            requires_review = False
        elif amount > self.REVIEW_THRESHOLD:
            approval_path = "manager_review"
            requires_review = True
        else:
            approval_path = "standard_review"
            requires_review = True

        policy_id = f"pol_{uuid.uuid4().hex[:10]}"

        return StepHandlerResult.success(
            result={
                "policy_id": policy_id,
                "request_id": request_id,
                "approval_path": approval_path,
                "requires_review": requires_review,
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
                "checked_at": datetime.now(timezone.utc).isoformat(),
            },
        )


class ApproveRefundHandler(StepHandler):
    """Approve the refund based on policy check results.

    For auto-approved refunds, generates approval immediately.
    For review-required refunds, simulates manager approval.
    """

    handler_name = "cs_approve_refund"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        validation = context.get_dependency_result("cs_validate_refund_request")
        policy = context.get_dependency_result("cs_check_refund_policy")

        if not all([validation, policy]):
            return StepHandlerResult.failure(
                message="Missing upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        request_id = validation.get("request_id")
        amount = validation.get("amount", 0.0)
        approval_path = policy.get("approval_path", "standard_review")
        requires_review = policy.get("requires_review", True)

        approval_id = f"apr_{uuid.uuid4().hex[:12]}"

        if approval_path == "auto_approved":
            approver = "system"
            approval_note = "Auto-approved per refund policy"
        elif approval_path == "manager_review":
            approver = "manager@example.com"
            approval_note = f"Manager-approved refund of ${amount:.2f}"
        else:
            approver = "cs_agent@example.com"
            approval_note = "Agent-reviewed and approved"

        return StepHandlerResult.success(
            result={
                "approval_id": approval_id,
                "request_id": request_id,
                "approved": True,
                "approver": approver,
                "approval_path": approval_path,
                "approval_note": approval_note,
                "amount_approved": amount,
                "approved_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"approval_path": approval_path},
        )


class ExecuteRefundHandler(StepHandler):
    """Execute the approved refund by initiating the financial transaction.

    This step bridges between the CustomerSuccess and Payments namespaces.
    In a real system, this might delegate to the Payments team's API.
    Here we simulate the refund execution.
    """

    handler_name = "cs_execute_refund"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        validation = context.get_dependency_result("cs_validate_refund_request")
        approval = context.get_dependency_result("cs_approve_refund")

        if not all([validation, approval]):
            return StepHandlerResult.failure(
                message="Missing upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        if not approval.get("approved"):
            return StepHandlerResult.failure(
                message="Refund was not approved",
                error_type=ErrorType.PERMANENT_ERROR,
                retryable=False,
                error_code="NOT_APPROVED",
            )

        amount = approval.get("amount_approved", 0.0)
        request_id = validation.get("request_id")
        order_ref = validation.get("order_ref")

        refund_id = f"rfnd_{uuid.uuid4().hex[:12]}"
        transaction_ref = f"txn_{uuid.uuid4().hex[:16]}"

        return StepHandlerResult.success(
            result={
                "refund_id": refund_id,
                "transaction_ref": transaction_ref,
                "request_id": request_id,
                "order_ref": order_ref,
                "amount_refunded": amount,
                "currency": "USD",
                "refund_method": "original_payment_method",
                "estimated_arrival": "3-5 business days",
                "status": "processed",
                "executed_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"gateway": "simulated"},
        )


class UpdateTicketHandler(StepHandler):
    """Update the customer support ticket with refund outcome.

    Creates a resolution summary on the support ticket, including
    all relevant reference IDs for audit trail.
    """

    handler_name = "cs_update_ticket"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        validation = context.get_dependency_result("cs_validate_refund_request")
        refund = context.get_dependency_result("cs_execute_refund")

        if not all([validation, refund]):
            return StepHandlerResult.failure(
                message="Missing upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        request_id = validation.get("request_id")
        customer_email = validation.get("customer_email")
        refund_id = refund.get("refund_id")
        amount = refund.get("amount_refunded", 0.0)
        order_ref = validation.get("order_ref")

        ticket_id = f"tkt_{uuid.uuid4().hex[:12]}"

        resolution_note = (
            f"Refund of ${amount:.2f} processed for order {order_ref}. "
            f"Refund ID: {refund_id}. Customer notified at {customer_email}. "
            f"Estimated arrival: 3-5 business days."
        )

        return StepHandlerResult.success(
            result={
                "ticket_id": ticket_id,
                "request_id": request_id,
                "resolution": "refund_completed",
                "resolution_note": resolution_note,
                "customer_notified": True,
                "notification_channel": "email",
                "refund_id": refund_id,
                "amount_refunded": amount,
                "ticket_status": "resolved",
                "resolved_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"resolution_type": "refund"},
        )
