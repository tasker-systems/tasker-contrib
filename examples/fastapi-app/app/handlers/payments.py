"""Payments namespace step handlers for refund processing.

4 sequential steps owned by the Payments team:
  ValidateEligibility -> ProcessGateway -> UpdateRecords -> NotifyCustomer

This is the Payments team's independent implementation of refund processing,
demonstrating namespace isolation. The Payments team owns the financial
validation, gateway interaction, and ledger updates, while CustomerSuccess
owns the customer-facing workflow.
"""

from __future__ import annotations

import hashlib
import uuid
from datetime import datetime, timezone
from typing import Any

from tasker_core import ErrorType, StepContext, StepHandler, StepHandlerResult


class ValidateEligibilityHandler(StepHandler):
    """Validate refund eligibility from the Payments perspective.

    Checks financial constraints: original transaction existence, refund
    window, partial refund limits, and fraud signals.
    """

    handler_name = "validate_payment_eligibility"
    handler_version = "1.0.0"

    REFUND_WINDOW_DAYS = 90
    MAX_PARTIAL_REFUND_PERCENT = 100.0

    def call(self, context: StepContext) -> StepHandlerResult:
        # Source-aligned: read payment_id, refund_amount, refund_reason, partial_refund
        payment_id = context.get_input("payment_id")
        refund_amount = context.get_input("refund_amount")
        _refund_reason = context.get_input("refund_reason")
        _partial_refund = context.get_input("partial_refund") or False

        # Also support app-specific context keys
        order_ref = context.get_input("order_ref") or payment_id
        amount = refund_amount or context.get_input("amount")
        reason = _refund_reason or context.get_input("reason") or "customer_request"
        customer_email = context.get_input("customer_email")

        if not payment_id and not order_ref:
            return StepHandlerResult.failure(
                message="Payment ID or order reference is required",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="MISSING_ORDER_REF",
            )

        if not amount or amount <= 0:
            return StepHandlerResult.failure(
                message=f"Invalid refund amount: {amount}",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="INVALID_AMOUNT",
            )

        # Simulate looking up the original transaction
        original_amount = amount + 1000  # Original was higher
        refund_percentage = round((amount / original_amount) * 100, 2)

        # Simulate fraud check
        fraud_key = f"{order_ref}:{customer_email}" if customer_email else f"{order_ref}:unknown"
        fraud_score = int(hashlib.md5(fraud_key.encode()).hexdigest()[:2], 16) / 255.0
        fraud_score = round(fraud_score * 100, 1)
        fraud_flagged = fraud_score > 85.0

        if fraud_flagged:
            return StepHandlerResult.failure(
                message=f"Transaction flagged for fraud review (score: {fraud_score})",
                error_type=ErrorType.PERMANENT_ERROR,
                retryable=False,
                error_code="FRAUD_FLAGGED",
            )

        eligibility_id = f"elig_{uuid.uuid4().hex[:12]}"
        now = datetime.now(timezone.utc).isoformat()

        return StepHandlerResult.success(
            result={
                "payment_validated": True,
                "payment_id": payment_id or order_ref,
                "original_amount": original_amount,
                "refund_amount": amount,
                "payment_method": "credit_card",
                "gateway_provider": "MockPaymentGateway",
                "eligibility_status": "eligible",
                "validation_timestamp": now,
                "namespace": "payments_py",
                "eligibility_id": eligibility_id,
                "order_ref": order_ref,
                "amount": amount,
                "refund_percentage": refund_percentage,
                "reason": reason,
                "customer_email": customer_email,
                "fraud_score": fraud_score,
                "fraud_flagged": False,
                "within_refund_window": True,
                "eligible": True,
                "validated_at": now,
            },
            metadata={"fraud_score": fraud_score},
        )


class ProcessGatewayHandler(StepHandler):
    """Process the refund through the payment gateway.

    Communicates with the simulated payment gateway to initiate the
    refund transaction. Handles gateway responses and generates
    transaction references.
    """

    handler_name = "process_gateway_refund"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        eligibility = context.get_dependency_result("validate_payment_eligibility")
        if eligibility is None or not eligibility.get("payment_validated"):
            return StepHandlerResult.failure(
                message="Missing validate_payment_eligibility dependency",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        # Source-aligned: read from dependency fields
        payment_id = context.get_dependency_field("validate_payment_eligibility", "payment_id")
        refund_amount = context.get_dependency_field("validate_payment_eligibility", "refund_amount")
        _original_amount = context.get_dependency_field("validate_payment_eligibility", "original_amount")

        # Source-aligned: read from task context
        refund_reason = context.get_input("refund_reason") or "customer_request"
        _partial_refund = context.get_input("partial_refund") or False

        amount = refund_amount or eligibility.get("amount", 0.0)
        order_ref = eligibility.get("order_ref")

        refund_id = f"rfnd_{uuid.uuid4().hex[:24]}"
        gateway_txn_id = f"gw_{uuid.uuid4().hex[:16]}"
        settlement_id = f"stl_{uuid.uuid4().hex[:12]}"
        authorization_code = hashlib.sha256(
            f"{gateway_txn_id}:{amount}".encode()
        ).hexdigest()[:8].upper()

        from datetime import timedelta

        now = datetime.now(timezone.utc)
        estimated_arrival = (now + timedelta(days=5)).isoformat()

        return StepHandlerResult.success(
            result={
                "refund_processed": True,
                "refund_id": refund_id,
                "payment_id": payment_id,
                "refund_amount": amount,
                "refund_status": "processed",
                "gateway_transaction_id": gateway_txn_id,
                "gateway_provider": "MockPaymentGateway",
                "processed_at": now.isoformat(),
                "estimated_arrival": estimated_arrival,
                "namespace": "payments_py",
                "gateway_txn_id": gateway_txn_id,
                "settlement_id": settlement_id,
                "authorization_code": authorization_code,
                "order_ref": order_ref,
                "amount_processed": amount,
                "currency": "USD",
                "gateway": "stripe_simulated",
                "gateway_status": "succeeded",
                "processor_response_code": "00",
                "processor_message": "Approved",
                "settlement_batch": now.strftime("%Y%m%d"),
            },
            metadata={
                "gateway": "stripe_simulated",
                "response_code": "00",
            },
        )


class UpdateRecordsHandler(StepHandler):
    """Update financial records and ledger entries for the refund.

    Creates ledger entries, updates account balances, and generates
    the audit trail for the refund transaction.
    """

    handler_name = "update_payment_records"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        refund_result = context.get_dependency_result("process_gateway_refund")

        if not refund_result or not refund_result.get("refund_processed"):
            return StepHandlerResult.failure(
                message="Missing upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        # Source-aligned: read from dependency fields
        payment_id = context.get_dependency_field("process_gateway_refund", "payment_id")
        refund_id = context.get_dependency_field("process_gateway_refund", "refund_id")
        refund_amount = context.get_dependency_field("process_gateway_refund", "refund_amount")
        gateway_transaction_id = context.get_dependency_field("process_gateway_refund", "gateway_transaction_id")
        _original_amount = context.get_dependency_field("validate_payment_eligibility", "original_amount")

        # Source-aligned: read from task context
        refund_reason = context.get_input("refund_reason") or "customer_request"

        eligibility = context.get_dependency_result("validate_payment_eligibility")
        amount = refund_amount or refund_result.get("amount_processed", 0.0)
        order_ref = (eligibility or {}).get("order_ref")
        gateway_txn_id = gateway_transaction_id or refund_result.get("gateway_txn_id")

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

        return StepHandlerResult.success(
            result={
                "records_updated": True,
                "payment_id": payment_id,
                "refund_id": refund_id,
                "record_id": record_id,
                "payment_status": "refunded",
                "refund_status": "completed",
                "history_entries_created": len(ledger_entries),
                "updated_at": now,
                "namespace": "payments_py",
                "journal_id": journal_id,
                "ledger_entries": ledger_entries,
                "order_ref": order_ref,
                "amount_recorded": amount,
                "gateway_txn_id": gateway_txn_id,
                "reconciliation_status": "pending",
                "fiscal_period": datetime.now(timezone.utc).strftime("%Y-%m"),
                "recorded_at": now,
            },
            metadata={"entries_created": len(ledger_entries)},
        )


class NotifyCustomerHandler(StepHandler):
    """Send refund confirmation notification to the customer.

    Composes and sends a notification email with all relevant refund
    details including transaction references and estimated arrival.
    """

    handler_name = "notify_customer"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        refund_result = context.get_dependency_result("process_gateway_refund")

        if not refund_result or not refund_result.get("refund_processed"):
            return StepHandlerResult.failure(
                message="Missing upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        # Source-aligned: read customer_email from task context
        customer_email = context.get_input("customer_email")
        if not customer_email:
            customer_email = "unknown@example.com"

        # Source-aligned: read from dependency fields
        refund_id = context.get_dependency_field("process_gateway_refund", "refund_id")
        refund_amount = context.get_dependency_field("process_gateway_refund", "refund_amount")
        _payment_id = context.get_dependency_field("process_gateway_refund", "payment_id")
        _estimated_arrival = context.get_dependency_field("process_gateway_refund", "estimated_arrival")

        # Source-aligned: read from task context
        _refund_reason = context.get_input("refund_reason") or "customer_request"

        eligibility = context.get_dependency_result("validate_payment_eligibility")
        records = context.get_dependency_result("update_payment_records")
        amount = refund_amount or refund_result.get("amount_processed", 0.0)
        order_ref = (eligibility or {}).get("order_ref")
        gateway_txn_id = refund_result.get("gateway_txn_id")
        journal_id = (records or {}).get("journal_id")

        message_id = f"msg_{uuid.uuid4().hex[:24]}"
        notification_id = f"ntf_{uuid.uuid4().hex[:12]}"
        now = datetime.now(timezone.utc).isoformat()

        subject = f"Refund Processed - Order {order_ref}"
        body_preview = (
            f"Your refund of ${amount:.2f} for order {order_ref} has been processed. "
            f"Reference: {gateway_txn_id}. "
            f"The refund will appear on your statement within 5-10 business days."
        )

        return StepHandlerResult.success(
            result={
                "notification_sent": True,
                "customer_email": customer_email,
                "message_id": message_id,
                "notification_type": "refund_confirmation",
                "sent_at": now,
                "delivery_status": "delivered",
                "refund_id": refund_id,
                "refund_amount": amount,
                "namespace": "payments_py",
                "notification_id": notification_id,
                "recipient": customer_email,
                "channel": "email",
                "subject": subject,
                "body_preview": body_preview,
                "template": "refund_confirmation_v2",
                "references": {
                    "order_ref": order_ref,
                    "gateway_txn_id": gateway_txn_id,
                    "journal_id": journal_id,
                },
                "status": "sent",
            },
            metadata={"email_provider": "simulated"},
        )
