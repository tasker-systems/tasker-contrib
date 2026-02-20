"""Payments business logic.

Pure functions that validate refund eligibility, process gateway refunds,
update financial records, and send customer notifications. No Tasker types
— just plain dicts in, typed models out.
"""

from __future__ import annotations

import hashlib
import uuid
from datetime import datetime, timedelta, timezone
from tasker_core.errors import PermanentError, RetryableError

from .types import (
    ValidatePaymentEligibilityInput,
    PaymentsNotifyCustomerResult,
    PaymentsProcessGatewayResult,
    PaymentsUpdateRecordsResult,
    PaymentsValidateEligibilityResult,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

REFUND_WINDOW_DAYS = 90
MAX_PARTIAL_REFUND_PERCENT = 100.0


# ---------------------------------------------------------------------------
# Service functions
# ---------------------------------------------------------------------------


def validate_eligibility(
    input: ValidatePaymentEligibilityInput,
) -> PaymentsValidateEligibilityResult:
    """Validate refund eligibility from the Payments perspective.

    Checks financial constraints: original transaction existence, refund
    window, partial refund limits, and fraud signals.
    """
    order_ref = input.order_ref or input.payment_id
    amount = input.refund_amount
    reason = input.refund_reason or "customer_request"
    customer_email = input.customer_email
    payment_id = input.payment_id

    # Fields guaranteed non-None by @model_validator (raises PermanentError if missing)
    assert amount is not None

    if amount <= 0:
        raise PermanentError(f"Invalid refund amount: {amount}")

    # Simulate looking up the original transaction
    original_amount = amount + 1000  # Original was higher
    refund_percentage = round((amount / original_amount) * 100, 2)

    # Simulate fraud check
    fraud_key = f"{order_ref}:{customer_email}" if customer_email else f"{order_ref}:unknown"
    fraud_score = int(hashlib.md5(fraud_key.encode()).hexdigest()[:2], 16) / 255.0
    fraud_score = round(fraud_score * 100, 1)
    fraud_flagged = fraud_score > 85.0

    if fraud_flagged:
        raise PermanentError(
            f"Transaction flagged for fraud review (score: {fraud_score})"
        )

    eligibility_id = f"elig_{uuid.uuid4().hex[:12]}"
    now = datetime.now(timezone.utc).isoformat()

    return PaymentsValidateEligibilityResult(
        payment_validated=True,
        payment_id=payment_id or order_ref,
        original_amount=original_amount,
        refund_amount=amount,
        payment_method="credit_card",
        gateway_provider="MockPaymentGateway",
        eligibility_status="eligible",
        validation_timestamp=now,
        namespace="payments_py",
        eligibility_id=eligibility_id,
        order_ref=order_ref,
        amount=amount,
        refund_percentage=refund_percentage,
        reason=reason,
        customer_email=customer_email,
        fraud_score=fraud_score,
        fraud_flagged=False,
        within_refund_window=True,
        eligible=True,
        validated_at=now,
    )


def process_gateway(
    eligibility: PaymentsValidateEligibilityResult,
    refund_reason: str | None,
    partial_refund: bool,
) -> PaymentsProcessGatewayResult:
    """Process the refund through the payment gateway.

    Communicates with the simulated payment gateway to initiate the
    refund transaction.
    """
    if not eligibility.payment_validated:
        raise PermanentError("Missing validate_payment_eligibility dependency")

    payment_id = eligibility.payment_id
    refund_amount = eligibility.refund_amount
    amount = refund_amount or eligibility.amount or 0.0
    order_ref = eligibility.order_ref

    refund_id = f"rfnd_{uuid.uuid4().hex[:24]}"
    gateway_txn_id = f"gw_{uuid.uuid4().hex[:16]}"
    settlement_id = f"stl_{uuid.uuid4().hex[:12]}"
    authorization_code = hashlib.sha256(
        f"{gateway_txn_id}:{amount}".encode()
    ).hexdigest()[:8].upper()

    now = datetime.now(timezone.utc)
    estimated_arrival = (now + timedelta(days=5)).isoformat()

    return PaymentsProcessGatewayResult(
        refund_processed=True,
        refund_id=refund_id,
        payment_id=payment_id,
        refund_amount=amount,
        refund_status="processed",
        gateway_transaction_id=gateway_txn_id,
        gateway_provider="MockPaymentGateway",
        processed_at=now.isoformat(),
        estimated_arrival=estimated_arrival,
        namespace="payments_py",
        gateway_txn_id=gateway_txn_id,
        settlement_id=settlement_id,
        authorization_code=authorization_code,
        order_ref=order_ref,
        amount_processed=amount,
        currency="USD",
        gateway="stripe_simulated",
        gateway_status="succeeded",
        processor_response_code="00",
        processor_message="Approved",
        settlement_batch=now.strftime("%Y%m%d"),
    )


def update_records(
    eligibility: PaymentsValidateEligibilityResult,
    refund_result: PaymentsProcessGatewayResult,
    refund_reason: str | None,
) -> PaymentsUpdateRecordsResult:
    """Update financial records and ledger entries for the refund.

    Creates ledger entries, updates account balances, and generates
    the audit trail for the refund transaction.
    """
    if not refund_result.refund_processed:
        raise PermanentError("Missing upstream dependency results")

    payment_id = refund_result.payment_id
    refund_id = refund_result.refund_id
    refund_amount = refund_result.refund_amount
    gateway_transaction_id = refund_result.gateway_transaction_id

    amount = refund_amount or refund_result.amount_processed or 0.0
    order_ref = eligibility.order_ref
    gateway_txn_id = gateway_transaction_id or refund_result.gateway_txn_id

    record_id = f"rec_{uuid.uuid4().hex[:16]}"
    ledger_entry_id = f"led_{uuid.uuid4().hex[:12]}"
    journal_id = f"jrn_{uuid.uuid4().hex[:10]}"
    now = datetime.now(timezone.utc).isoformat()

    ledger_entries = [
        {
            "entry_id": ledger_entry_id,
            "type": "debit",
            "account": "refunds_payable",
            "amount": amount,
            "reference": gateway_txn_id,
        },
        {
            "entry_id": f"led_{uuid.uuid4().hex[:12]}",
            "type": "credit",
            "account": "accounts_receivable",
            "amount": amount,
            "reference": gateway_txn_id,
        },
    ]

    return PaymentsUpdateRecordsResult(
        records_updated=True,
        payment_id=payment_id,
        refund_id=refund_id,
        record_id=record_id,
        payment_status="refunded",
        refund_status="completed",
        history_entries_created=len(ledger_entries),
        updated_at=now,
        namespace="payments_py",
        journal_id=journal_id,
        ledger_entries=ledger_entries,
        order_ref=order_ref,
        amount_recorded=amount,
        gateway_txn_id=gateway_txn_id,
        reconciliation_status="pending",
        fiscal_period=datetime.now(timezone.utc).strftime("%Y-%m"),
        recorded_at=now,
    )


def notify_customer(
    eligibility: PaymentsValidateEligibilityResult,
    refund_result: PaymentsProcessGatewayResult,
    records: PaymentsUpdateRecordsResult,
    customer_email: str | None,
) -> PaymentsNotifyCustomerResult:
    """Send refund confirmation notification to the customer.

    Composes and sends a notification email with all relevant refund
    details including transaction references and estimated arrival.
    """
    if not refund_result.refund_processed:
        raise PermanentError("Missing upstream dependency results")

    customer_email = customer_email or "unknown@example.com"

    refund_id = refund_result.refund_id
    refund_amount = refund_result.refund_amount
    amount = refund_amount or refund_result.amount_processed or 0.0
    order_ref = eligibility.order_ref
    gateway_txn_id = refund_result.gateway_txn_id
    journal_id = records.journal_id

    message_id = f"msg_{uuid.uuid4().hex[:24]}"
    notification_id = f"ntf_{uuid.uuid4().hex[:12]}"
    now = datetime.now(timezone.utc).isoformat()

    subject = f"Refund Processed - Order {order_ref}"
    body_preview = (
        f"Your refund of ${amount:.2f} for order {order_ref} has been processed. "
        f"Reference: {gateway_txn_id}. "
        f"The refund will appear on your statement within 5-10 business days."
    )

    return PaymentsNotifyCustomerResult(
        notification_sent=True,
        customer_email=customer_email,
        message_id=message_id,
        notification_type="refund_confirmation",
        sent_at=now,
        delivery_status="delivered",
        refund_id=refund_id,
        refund_amount=amount,
        namespace="payments_py",
        notification_id=notification_id,
        recipient=customer_email,
        channel="email",
        subject=subject,
        body_preview=body_preview,
        template="refund_confirmation_v2",
        references={
            "order_ref": order_ref,
            "gateway_txn_id": gateway_txn_id,
            "journal_id": journal_id,
        },
        status="sent",
    )
