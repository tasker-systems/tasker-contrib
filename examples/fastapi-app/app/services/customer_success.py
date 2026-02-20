"""Customer Success business logic.

Pure functions for refund processing: validation, policy checking, approval,
execution, and ticket updates. No Tasker types — just plain dicts in, typed
models out.
"""

from __future__ import annotations

import hashlib
import uuid
from datetime import datetime, timedelta, timezone
from tasker_core.errors import PermanentError, RetryableError

from .types import (
    ValidateRefundRequestInput,
    CustomerSuccessApproveRefundResult,
    CustomerSuccessCheckPolicyResult,
    CustomerSuccessExecuteRefundResult,
    CustomerSuccessUpdateTicketResult,
    CustomerSuccessValidateRefundResult,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

VALID_REASONS = {
    "customer_request",
    "defective_product",
    "wrong_item",
    "late_delivery",
    "duplicate_charge",
    "service_issue",
}

MAX_REFUND_AMOUNT = 10000.00
AUTO_APPROVE_THRESHOLD = 50.00
REVIEW_THRESHOLD = 500.00
AUTO_APPROVE_REASONS = {"defective_product", "wrong_item", "duplicate_charge"}


# ---------------------------------------------------------------------------
# Service functions
# ---------------------------------------------------------------------------


def validate_refund_request(
    input: ValidateRefundRequestInput,
) -> CustomerSuccessValidateRefundResult:
    """Validate that the refund request is well-formed and eligible."""
    order_ref = input.resolved_ticket_id
    amount = input.resolved_amount
    reason = input.refund_reason
    customer_id = input.customer_id

    # Fields guaranteed non-None by @model_validator (raises PermanentError if missing)
    assert amount is not None
    assert customer_id is not None

    if amount <= 0:
        raise PermanentError(f"Refund amount must be positive, got: {amount}")

    if amount > MAX_REFUND_AMOUNT:
        raise PermanentError(
            f"Refund amount ${amount:.2f} exceeds maximum ${MAX_REFUND_AMOUNT:.2f}"
        )

    if reason and reason not in VALID_REASONS:
        raise PermanentError(
            f"Invalid refund reason: {reason}. Valid: {', '.join(sorted(VALID_REASONS))}"
        )

    request_id = f"ref_{uuid.uuid4().hex[:12]}"
    validation_hash = hashlib.sha256(
        f"{order_ref}:{amount}:{reason}:{input.customer_email}".encode()
    ).hexdigest()[:16]
    payment_id = f"pay_{uuid.uuid4().hex[:12]}"

    # Determine customer tier based on customer_id
    customer_tier = "standard"
    cid = customer_id.lower()
    if "vip" in cid or "premium" in cid:
        customer_tier = "premium"
    elif "gold" in cid:
        customer_tier = "gold"

    original_purchase_date = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    now = datetime.now(timezone.utc).isoformat()

    return CustomerSuccessValidateRefundResult(
        request_validated=True,
        ticket_id=input.ticket_id,
        customer_id=input.customer_id,
        ticket_status="open",
        customer_tier=customer_tier,
        original_purchase_date=original_purchase_date,
        payment_id=payment_id,
        validation_timestamp=now,
        namespace="customer_success_py",
        request_id=request_id,
        order_ref=order_ref,
        amount=amount,
        reason=reason or "customer_request",
        customer_email=input.customer_email,
        validation_hash=validation_hash,
        eligible=True,
        validated_at=now,
    )


def check_refund_policy(
    validation: CustomerSuccessValidateRefundResult,
    refund_amount: float | None = None,
) -> CustomerSuccessCheckPolicyResult:
    """Check the refund request against company refund policies."""
    if not validation.request_validated:
        raise PermanentError("Missing validate_refund_request dependency")

    customer_tier = validation.customer_tier or "standard"
    original_purchase_date = validation.original_purchase_date
    amount = refund_amount or validation.amount or 0.0
    reason = validation.reason or "customer_request"
    request_id = validation.request_id

    # Determine approval path
    if amount <= AUTO_APPROVE_THRESHOLD:
        approval_path = "auto_approved"
        requires_approval = False
    elif reason in AUTO_APPROVE_REASONS and amount <= REVIEW_THRESHOLD:
        approval_path = "auto_approved"
        requires_approval = False
    elif amount > REVIEW_THRESHOLD:
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
            purchase_date = datetime.fromisoformat(
                original_purchase_date.replace("Z", "+00:00")
            )
            days_since_purchase = (datetime.now(timezone.utc) - purchase_date).days
        except (ValueError, TypeError):
            pass

    return CustomerSuccessCheckPolicyResult(
        policy_checked=True,
        policy_compliant=True,
        customer_tier=customer_tier,
        refund_window_days=refund_window_days,
        days_since_purchase=days_since_purchase,
        within_refund_window=days_since_purchase <= refund_window_days,
        requires_approval=requires_approval,
        max_allowed_amount=MAX_REFUND_AMOUNT,
        policy_checked_at=now,
        namespace="customer_success_py",
        policy_id=policy_id,
        request_id=request_id,
        approval_path=approval_path,
        requires_review=requires_approval,
        amount_tier=(
            "small" if amount <= AUTO_APPROVE_THRESHOLD
            else "medium" if amount <= REVIEW_THRESHOLD
            else "large"
        ),
        policy_version="2026.1",
        rules_applied=[
            f"amount_threshold_{AUTO_APPROVE_THRESHOLD}",
            f"reason_category_{reason}",
            f"review_threshold_{REVIEW_THRESHOLD}",
        ],
        checked_at=now,
    )


def approve_refund(
    policy: CustomerSuccessCheckPolicyResult,
    validation: CustomerSuccessValidateRefundResult,
    refund_amount: float | None = None,
) -> CustomerSuccessApproveRefundResult:
    """Approve the refund based on policy check results."""
    if not policy.policy_checked:
        raise PermanentError("Missing check_refund_policy dependency")

    request_id = validation.request_id
    amount = refund_amount or validation.amount or 0.0
    approval_path = policy.approval_path or "standard_review"
    requires_approval = policy.requires_approval or False
    customer_tier = policy.customer_tier or "standard"
    ticket_id = validation.ticket_id
    customer_id = validation.customer_id

    approval_id = f"apr_{uuid.uuid4().hex[:12]}"
    now = datetime.now(timezone.utc).isoformat()

    if requires_approval:
        manager_id = f"mgr_{(hash(ticket_id or '') % 5) + 1}"
        manager_notes = f"Manager-approved refund of ${amount:.2f} for customer {customer_id}"

        return CustomerSuccessApproveRefundResult(
            approval_obtained=True,
            approval_required=True,
            auto_approved=False,
            approval_id=approval_id,
            manager_id=manager_id,
            manager_notes=manager_notes,
            approved_at=now,
            namespace="customer_success_py",
            request_id=request_id,
            approved=True,
            approver=manager_id,
            approval_path=approval_path,
            approval_note=manager_notes,
            amount_approved=amount,
        )
    else:
        return CustomerSuccessApproveRefundResult(
            approval_obtained=True,
            approval_required=False,
            auto_approved=True,
            approval_id=None,
            manager_id=None,
            manager_notes=f"Auto-approved for customer tier {customer_tier}",
            approved_at=now,
            namespace="customer_success_py",
            request_id=request_id,
            approved=True,
            approver="system",
            approval_path=approval_path,
            approval_note="Auto-approved per refund policy",
            amount_approved=amount,
        )


def execute_refund(
    approval: CustomerSuccessApproveRefundResult,
    validation: CustomerSuccessValidateRefundResult,
    refund_amount: float | None = None,
    correlation_id: str | None = None,
) -> CustomerSuccessExecuteRefundResult:
    """Execute the approved refund by initiating the financial transaction."""
    if not approval.approval_obtained:
        raise PermanentError("Refund was not approved")

    amount = refund_amount or approval.amount_approved or 0.0
    request_id = validation.request_id
    order_ref = validation.order_ref
    correlation_id = correlation_id or f"cs-{uuid.uuid4().hex[:16]}"

    delegated_task_id = f"task_{uuid.uuid4()}"
    refund_id = f"rfnd_{uuid.uuid4().hex[:12]}"
    transaction_ref = f"txn_{uuid.uuid4().hex[:16]}"
    now = datetime.now(timezone.utc).isoformat()

    return CustomerSuccessExecuteRefundResult(
        task_delegated=True,
        target_namespace="payments_py",
        target_workflow="process_refund",
        delegated_task_id=delegated_task_id,
        delegated_task_status="created",
        delegation_timestamp=now,
        correlation_id=correlation_id,
        namespace="customer_success_py",
        refund_id=refund_id,
        transaction_ref=transaction_ref,
        request_id=request_id,
        order_ref=order_ref,
        amount_refunded=amount,
        currency="USD",
        refund_method="original_payment_method",
        estimated_arrival="3-5 business days",
        status="processed",
        executed_at=now,
    )


def update_ticket(
    delegation_result: CustomerSuccessExecuteRefundResult,
    validation: CustomerSuccessValidateRefundResult,
    refund_amount: float | None = None,
) -> CustomerSuccessUpdateTicketResult:
    """Update the customer support ticket with refund outcome."""
    if not delegation_result.task_delegated:
        raise PermanentError("Missing upstream dependency results")

    ticket_id = validation.ticket_id
    customer_id = validation.customer_id
    delegated_task_id = delegation_result.delegated_task_id
    correlation_id = delegation_result.correlation_id
    request_id = validation.request_id
    customer_email = validation.customer_email
    refund_id = delegation_result.refund_id
    amount = refund_amount or delegation_result.amount_refunded or 0.0
    order_ref = validation.order_ref

    now = datetime.now(timezone.utc).isoformat()

    resolution_note = (
        f"Refund of ${amount:.2f} processed for order {order_ref}. "
        f"Refund ID: {refund_id}. Customer notified at {customer_email}. "
        f"Delegated task ID: {delegated_task_id}. "
        f"Correlation ID: {correlation_id}. "
        f"Estimated arrival: 3-5 business days."
    )

    return CustomerSuccessUpdateTicketResult(
        ticket_updated=True,
        ticket_id=ticket_id or f"tkt_{uuid.uuid4().hex[:12]}",
        previous_status="in_progress",
        new_status="resolved",
        resolution_note=resolution_note,
        updated_at=now,
        refund_completed=True,
        delegated_task_id=delegated_task_id,
        namespace="customer_success_py",
        request_id=request_id,
        resolution="refund_completed",
        customer_notified=True,
        notification_channel="email",
        refund_id=refund_id,
        amount_refunded=amount,
        ticket_status="resolved",
        resolved_at=now,
    )
