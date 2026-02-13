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

    handler_name = "pay_validate_eligibility"
    handler_version = "1.0.0"

    REFUND_WINDOW_DAYS = 90
    MAX_PARTIAL_REFUND_PERCENT = 100.0

    def call(self, context: StepContext) -> StepHandlerResult:
        order_ref = context.get_input("order_ref")
        amount = context.get_input("amount")
        reason = context.get_input("reason") or "customer_request"
        customer_email = context.get_input("customer_email")

        if not order_ref:
            return StepHandlerResult.failure(
                message="Order reference is required",
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
        original_amount = amount * 1.0  # In real system, look up actual amount
        refund_percentage = round((amount / original_amount) * 100, 2)

        # Simulate fraud check
        fraud_score = int(hashlib.md5(f"{order_ref}:{customer_email}".encode()).hexdigest()[:2], 16) / 255.0
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

        return StepHandlerResult.success(
            result={
                "eligibility_id": eligibility_id,
                "order_ref": order_ref,
                "amount": amount,
                "original_amount": original_amount,
                "refund_percentage": refund_percentage,
                "reason": reason,
                "customer_email": customer_email,
                "fraud_score": fraud_score,
                "fraud_flagged": False,
                "within_refund_window": True,
                "eligible": True,
                "validated_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"fraud_score": fraud_score},
        )


class ProcessGatewayHandler(StepHandler):
    """Process the refund through the payment gateway.

    Communicates with the simulated payment gateway to initiate the
    refund transaction. Handles gateway responses and generates
    transaction references.
    """

    handler_name = "pay_process_gateway"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        eligibility = context.get_dependency_result("pay_validate_eligibility")
        if eligibility is None:
            return StepHandlerResult.failure(
                message="Missing pay_validate_eligibility dependency",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        if not eligibility.get("eligible"):
            return StepHandlerResult.failure(
                message="Refund not eligible per validation",
                error_type=ErrorType.PERMANENT_ERROR,
                retryable=False,
                error_code="NOT_ELIGIBLE",
            )

        amount = eligibility.get("amount", 0.0)
        order_ref = eligibility.get("order_ref")

        gateway_txn_id = f"gw_{uuid.uuid4().hex[:16]}"
        settlement_id = f"stl_{uuid.uuid4().hex[:12]}"
        authorization_code = hashlib.sha256(
            f"{gateway_txn_id}:{amount}".encode()
        ).hexdigest()[:8].upper()

        return StepHandlerResult.success(
            result={
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
                "settlement_batch": datetime.now(timezone.utc).strftime("%Y%m%d"),
                "processed_at": datetime.now(timezone.utc).isoformat(),
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

    handler_name = "pay_update_records"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        eligibility = context.get_dependency_result("pay_validate_eligibility")
        gateway = context.get_dependency_result("pay_process_gateway")

        if not all([eligibility, gateway]):
            return StepHandlerResult.failure(
                message="Missing upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        amount = gateway.get("amount_processed", 0.0)
        order_ref = eligibility.get("order_ref")
        gateway_txn_id = gateway.get("gateway_txn_id")

        ledger_entry_id = f"led_{uuid.uuid4().hex[:12]}"
        journal_id = f"jrn_{uuid.uuid4().hex[:10]}"

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
                "journal_id": journal_id,
                "ledger_entries": ledger_entries,
                "order_ref": order_ref,
                "amount_recorded": amount,
                "gateway_txn_id": gateway_txn_id,
                "reconciliation_status": "pending",
                "fiscal_period": datetime.now(timezone.utc).strftime("%Y-%m"),
                "recorded_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"entries_created": len(ledger_entries)},
        )


class NotifyCustomerHandler(StepHandler):
    """Send refund confirmation notification to the customer.

    Composes and sends a notification email with all relevant refund
    details including transaction references and estimated arrival.
    """

    handler_name = "pay_notify_customer"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        eligibility = context.get_dependency_result("pay_validate_eligibility")
        gateway = context.get_dependency_result("pay_process_gateway")
        records = context.get_dependency_result("pay_update_records")

        if not all([eligibility, gateway, records]):
            return StepHandlerResult.failure(
                message="Missing upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        customer_email = eligibility.get("customer_email", "unknown@example.com")
        amount = gateway.get("amount_processed", 0.0)
        order_ref = eligibility.get("order_ref")
        gateway_txn_id = gateway.get("gateway_txn_id")
        journal_id = records.get("journal_id")

        notification_id = f"ntf_{uuid.uuid4().hex[:12]}"

        subject = f"Refund Processed - Order {order_ref}"
        body_preview = (
            f"Your refund of ${amount:.2f} for order {order_ref} has been processed. "
            f"Reference: {gateway_txn_id}. "
            f"The refund will appear on your statement within 5-10 business days."
        )

        return StepHandlerResult.success(
            result={
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
                "sent_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"email_provider": "simulated"},
        )
