/**
 * Customer Success namespace step handlers for refund processing.
 *
 * 5 sequential steps owned by the Customer Success team:
 *   ValidateRefundRequest -> CheckRefundEligibility -> CalculateRefundAmount
 *       -> NotifyCustomerSuccess -> UpdateCrmRecord
 *
 * Thin DSL wrappers that delegate to ../services/customer-success for business logic.
 */

import { defineHandler, PermanentError } from '@tasker-systems/tasker';
import * as svc from '../services/customer-success';

export const ValidateRefundRequestHandler = defineHandler(
  'CustomerSuccess.StepHandlers.ValidateRefundRequestHandler',
  {
    inputs: {
      ticketId: 'ticket_id',
      customerId: 'customer_id',
      refundAmount: 'refund_amount',
      refundReason: 'refund_reason',
    },
  },
  async ({ ticketId, customerId, refundAmount, refundReason }) => {
    const missingFields: string[] = [];
    if (!ticketId) missingFields.push('ticket_id');
    if (!customerId) missingFields.push('customer_id');
    if (!refundAmount) missingFields.push('refund_amount');

    if (missingFields.length > 0) {
      throw new PermanentError(
        `Missing required fields for refund validation: ${missingFields.join(', ')}`,
      );
    }

    return svc.validateRefundRequest({
      ticketId: ticketId as string,
      customerId: customerId as string,
      refundAmount: refundAmount as number,
      refundReason: (refundReason as string) || 'customer_request',
    });
  },
);

export const CheckRefundEligibilityHandler = defineHandler(
  'CustomerSuccess.StepHandlers.CheckRefundEligibilityHandler',
  {
    depends: { validationResult: 'validate_refund_request' },
    inputs: { refundAmount: 'refund_amount' },
  },
  async ({ validationResult, refundAmount }) =>
    svc.checkRefundEligibility(
      validationResult as Record<string, unknown>,
      refundAmount as number | undefined,
    ),
);

export const CalculateRefundAmountHandler = defineHandler(
  'CustomerSuccess.StepHandlers.CalculateRefundAmountHandler',
  {
    depends: {
      policyResult: 'check_refund_policy',
      validationResult: 'validate_refund_request',
    },
  },
  async ({ policyResult, validationResult }) =>
    svc.calculateRefundAmount(
      policyResult as Record<string, unknown>,
      (validationResult as Record<string, unknown>)?.customer_id as string | undefined,
    ),
);

export const NotifyCustomerSuccessHandler = defineHandler(
  'CustomerSuccess.StepHandlers.NotifyCustomerSuccessHandler',
  {
    depends: {
      approvalResult: 'get_manager_approval',
      validationResult: 'validate_refund_request',
    },
    inputs: { correlationId: 'correlation_id' },
  },
  async ({ approvalResult, validationResult, correlationId }) =>
    svc.notifyCustomerSuccess(
      approvalResult as Record<string, unknown>,
      validationResult as Record<string, unknown>,
      correlationId as string | undefined,
    ),
);

export const UpdateCrmRecordHandler = defineHandler(
  'CustomerSuccess.StepHandlers.UpdateCrmRecordHandler',
  {
    depends: {
      delegationResult: 'execute_refund_workflow',
      validationResult: 'validate_refund_request',
    },
    inputs: { refundAmount: 'refund_amount' },
  },
  async ({ delegationResult, validationResult, refundAmount }) =>
    svc.updateCrmRecord(
      delegationResult as Record<string, unknown>,
      validationResult as Record<string, unknown>,
      refundAmount as number | undefined,
    ),
);
