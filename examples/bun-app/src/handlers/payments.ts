/**
 * Payments namespace step handlers for refund processing.
 *
 * 4 sequential steps owned by the Payments team:
 *   ProcessRefundPayment -> UpdateLedger -> ReconcileAccount -> GenerateRefundReceipt
 *
 * Thin DSL wrappers that delegate to ../services/payments for business logic.
 */

import { defineHandler, PermanentError } from '@tasker-systems/tasker';
import * as svc from '../services/payments';

export const ProcessRefundPaymentHandler = defineHandler(
  'Payments.StepHandlers.ProcessRefundPaymentHandler',
  {
    inputs: {
      paymentId: 'payment_id',
      refundAmount: 'refund_amount',
    },
  },
  async ({ paymentId, refundAmount }) => {
    const missingFields: string[] = [];
    if (!paymentId) missingFields.push('payment_id');
    if (!refundAmount) missingFields.push('refund_amount');

    if (missingFields.length > 0) {
      throw new PermanentError(
        `Missing required fields for payment validation: ${missingFields.join(', ')}`,
      );
    }

    return svc.validateEligibility({
      paymentId: paymentId as string,
      refundAmount: refundAmount as number,
    });
  },
);

export const UpdateLedgerHandler = defineHandler(
  'Payments.StepHandlers.UpdateLedgerHandler',
  {
    depends: { validationResult: 'validate_payment_eligibility' },
  },
  async ({ validationResult }) =>
    svc.processGateway(validationResult as Record<string, unknown> | undefined),
);

export const ReconcileAccountHandler = defineHandler(
  'Payments.StepHandlers.ReconcileAccountHandler',
  {
    depends: { refundResult: 'process_gateway_refund' },
  },
  async ({ refundResult }) =>
    svc.updateRecords(refundResult as Record<string, unknown> | undefined),
);

export const GenerateRefundReceiptHandler = defineHandler(
  'Payments.StepHandlers.GenerateRefundReceiptHandler',
  {
    depends: { refundResult: 'process_gateway_refund' },
    inputs: { customerEmail: 'customer_email' },
  },
  async ({ refundResult, customerEmail }) =>
    svc.notifyCustomer(
      refundResult as Record<string, unknown> | undefined,
      customerEmail as string | undefined,
    ),
);
