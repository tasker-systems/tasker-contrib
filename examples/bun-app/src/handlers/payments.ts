import {
  StepHandler,
  type StepContext,
  type StepHandlerResult,
  ErrorType,
} from '@tasker-systems/tasker';

// ---------------------------------------------------------------------------
// Payments Namespace - Refund Payment Processing (4 steps)
// Demonstrates namespace isolation in the team scaling pattern.
// This namespace operates independently from customer_success but shares
// a parent_correlation_id for cross-namespace traceability.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Step 1: ProcessRefundPayment
// ---------------------------------------------------------------------------

export class ProcessRefundPaymentHandler extends StepHandler {
  static handlerName = 'Payments.StepHandlers.ValidatePaymentEligibilityHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      // TAS-137: Use getInput() matching source key names
      const paymentId = context.getInput('payment_id') as string | undefined;
      const refundAmount = context.getInput('refund_amount') as number | undefined;
      const _partialRefund = context.getInput('partial_refund') as boolean | undefined;

      // Validate required fields
      const missingFields: string[] = [];
      if (!paymentId) missingFields.push('payment_id');
      if (!refundAmount) missingFields.push('refund_amount');

      if (missingFields.length > 0) {
        return this.failure(
          `Missing required fields for payment validation: ${missingFields.join(', ')}`,
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const validPaymentId = paymentId as string;
      const validRefundAmount = refundAmount as number;

      if (validRefundAmount <= 0) {
        return this.failure(
          `Refund amount must be positive, got: ${validRefundAmount}`,
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const now = new Date().toISOString();

      return this.success(
        {
          payment_validated: true,
          payment_id: validPaymentId,
          original_amount: validRefundAmount + 1000,
          refund_amount: validRefundAmount,
          payment_method: 'credit_card',
          gateway_provider: 'MockPaymentGateway',
          eligibility_status: 'eligible',
          validation_timestamp: now,
          namespace: 'payments',
        },
        { gateway_response_ms: Math.random() * 300 + 200 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.RETRYABLE_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 2: UpdateLedger (depends on ProcessRefundPayment)
// ---------------------------------------------------------------------------

export class UpdateLedgerHandler extends StepHandler {
  static handlerName = 'Payments.StepHandlers.ProcessGatewayRefundHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      // TAS-137: Read dependency results matching source key names
      const validationResult = context.getDependencyResult('validate_payment_eligibility') as Record<string, unknown>;

      if (!validationResult?.payment_validated) {
        return this.failure(
          'Payment validation must be completed before processing refund',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const paymentId = validationResult.payment_id as string;
      const refundAmount = validationResult.refund_amount as number;

      const now = new Date();
      const estimatedArrival = new Date(now.getTime() + 5 * 24 * 60 * 60 * 1000).toISOString();

      return this.success(
        {
          refund_processed: true,
          refund_id: `rfnd_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
          payment_id: paymentId,
          refund_amount: refundAmount,
          refund_status: 'processed',
          gateway_transaction_id: `gtx_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
          gateway_provider: 'MockPaymentGateway',
          processed_at: now.toISOString(),
          estimated_arrival: estimatedArrival,
          namespace: 'payments',
        },
        { ledger_update_ms: Math.random() * 80 + 20 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 3: ReconcileAccount (depends on UpdateLedger)
// ---------------------------------------------------------------------------

export class ReconcileAccountHandler extends StepHandler {
  static handlerName = 'Payments.StepHandlers.UpdatePaymentRecordsHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      // TAS-137: Read dependency results matching source key names
      const refundResult = context.getDependencyResult('process_gateway_refund') as Record<string, unknown>;

      if (!refundResult?.refund_processed) {
        return this.failure(
          'Gateway refund must be completed before updating records',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const paymentId = refundResult.payment_id as string;
      const refundId = refundResult.refund_id as string;

      const now = new Date().toISOString();

      return this.success(
        {
          records_updated: true,
          payment_id: paymentId,
          refund_id: refundId,
          record_id: `rec_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
          payment_status: 'refunded',
          refund_status: 'completed',
          history_entries_created: 2,
          updated_at: now,
          namespace: 'payments',
        },
        { reconciliation_time_ms: Math.random() * 200 + 50 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 4: GenerateRefundReceipt (depends on ReconcileAccount -- final step)
// ---------------------------------------------------------------------------

export class GenerateRefundReceiptHandler extends StepHandler {
  static handlerName = 'Payments.StepHandlers.NotifyCustomerHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      // TAS-137: Read dependency results matching source key names
      const refundResult = context.getDependencyResult('process_gateway_refund') as Record<string, unknown>;

      if (!refundResult?.refund_processed) {
        return this.failure(
          'Refund must be processed before sending notification',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const customerEmail = context.getInput('customer_email') as string | undefined;
      if (!customerEmail) {
        return this.failure(
          'Customer email is required for notification',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const refundId = refundResult.refund_id as string;
      const refundAmount = refundResult.refund_amount as number;

      const now = new Date().toISOString();

      return this.success(
        {
          notification_sent: true,
          customer_email: customerEmail,
          message_id: `msg_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
          notification_type: 'refund_confirmation',
          sent_at: now,
          delivery_status: 'delivered',
          refund_id: refundId,
          refund_amount: refundAmount,
          namespace: 'payments',
        },
        { receipt_generation_ms: Math.random() * 300 + 80 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}
