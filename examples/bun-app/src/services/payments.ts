/**
 * Payments business logic.
 *
 * Pure functions that validate refund eligibility, process gateway refunds,
 * update financial records, and send customer notifications. No Tasker types
 * — just plain objects in, plain objects out.
 */

import { PermanentError } from '@tasker-systems/tasker';

import type {
  ValidatePaymentEligibilityInput,
  PaymentsValidateEligibilityResult,
  PaymentsProcessGatewayResult,
  PaymentsUpdateRecordsResult,
  PaymentsNotifyCustomerResult,
} from './types';

// ---------------------------------------------------------------------------
// Service functions
// ---------------------------------------------------------------------------

export function validateEligibility(
  input: ValidatePaymentEligibilityInput,
): PaymentsValidateEligibilityResult {
  if (input.refundAmount <= 0) {
    throw new PermanentError(
      `Refund amount must be positive, got: ${input.refundAmount}`,
    );
  }

  const now = new Date().toISOString();

  return {
    payment_validated: true,
    payment_id: input.paymentId,
    original_amount: input.refundAmount + 1000,
    refund_amount: input.refundAmount,
    payment_method: 'credit_card',
    gateway_provider: 'MockPaymentGateway',
    eligibility_status: 'eligible',
    validation_timestamp: now,
    namespace: 'payments_ts',
  };
}

export function processGateway(
  validationResult: Record<string, unknown> | undefined,
): PaymentsProcessGatewayResult {
  if (!validationResult?.payment_validated) {
    throw new PermanentError(
      'Payment validation must be completed before processing refund',
    );
  }

  const paymentId = validationResult.payment_id as string;
  const refundAmount = validationResult.refund_amount as number;

  const now = new Date();
  const estimatedArrival = new Date(now.getTime() + 5 * 24 * 60 * 60 * 1000).toISOString();

  return {
    refund_processed: true,
    refund_id: `rfnd_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
    payment_id: paymentId,
    refund_amount: refundAmount,
    refund_status: 'processed',
    gateway_transaction_id: `gtx_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
    gateway_provider: 'MockPaymentGateway',
    processed_at: now.toISOString(),
    estimated_arrival: estimatedArrival,
    namespace: 'payments_ts',
  };
}

export function updateRecords(
  refundResult: Record<string, unknown> | undefined,
): PaymentsUpdateRecordsResult {
  if (!refundResult?.refund_processed) {
    throw new PermanentError(
      'Gateway refund must be completed before updating records',
    );
  }

  const paymentId = refundResult.payment_id as string;
  const refundId = refundResult.refund_id as string;

  const now = new Date().toISOString();

  return {
    records_updated: true,
    payment_id: paymentId,
    refund_id: refundId,
    record_id: `rec_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
    payment_status: 'refunded',
    refund_status: 'completed',
    history_entries_created: 2,
    updated_at: now,
    namespace: 'payments_ts',
  };
}

export function notifyCustomer(
  refundResult: Record<string, unknown> | undefined,
  customerEmail: string | undefined,
): PaymentsNotifyCustomerResult {
  if (!refundResult?.refund_processed) {
    throw new PermanentError(
      'Refund must be processed before sending notification',
    );
  }

  if (!customerEmail) {
    throw new PermanentError('Customer email is required for notification');
  }

  const refundId = refundResult.refund_id as string;
  const refundAmount = refundResult.refund_amount as number;

  const now = new Date().toISOString();

  return {
    notification_sent: true,
    customer_email: customerEmail,
    message_id: `msg_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
    notification_type: 'refund_confirmation',
    sent_at: now,
    delivery_status: 'delivered',
    refund_id: refundId,
    refund_amount: refundAmount,
    namespace: 'payments_ts',
  };
}
