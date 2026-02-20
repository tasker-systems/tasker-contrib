/**
 * Customer Success business logic.
 *
 * Pure functions for refund processing: validation, policy checking, approval,
 * execution, and ticket updates. No Tasker types — just plain objects in,
 * plain objects out.
 */

import { PermanentError } from '@tasker-systems/tasker';

import type {
  ValidateRefundRequestInput,
  CustomerSuccessValidateRefundResult,
  CustomerSuccessCheckRefundPolicyResult,
  CustomerSuccessApproveRefundResult,
  CustomerSuccessExecuteRefundResult,
  CustomerSuccessUpdateTicketResult,
} from './types';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_REFUND_AMOUNT = 10_000;

const REFUND_POLICIES: Record<string, { window_days: number; requires_approval: boolean; max_amount: number }> = {
  standard: { window_days: 30, requires_approval: true, max_amount: 10_000 },
  gold: { window_days: 60, requires_approval: false, max_amount: 50_000 },
  premium: { window_days: 90, requires_approval: false, max_amount: 100_000 },
};

// ---------------------------------------------------------------------------
// Service functions
// ---------------------------------------------------------------------------

export function validateRefundRequest(
  input: ValidateRefundRequestInput,
): CustomerSuccessValidateRefundResult {
  // Determine customer tier
  let customerTier = 'standard';
  if (input.customerId.toLowerCase().includes('vip') || input.customerId.toLowerCase().includes('premium')) {
    customerTier = 'premium';
  } else if (input.customerId.toLowerCase().includes('gold')) {
    customerTier = 'gold';
  }

  const purchaseDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const now = new Date().toISOString();

  return {
    request_validated: true,
    ticket_id: input.ticketId,
    customer_id: input.customerId,
    ticket_status: 'open',
    customer_tier: customerTier,
    original_purchase_date: purchaseDate,
    payment_id: `pay_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
    validation_timestamp: now,
    namespace: 'customer_success_ts',
  };
}

export function checkRefundEligibility(
  validationResult: Record<string, unknown>,
  refundAmount: number | undefined,
): CustomerSuccessCheckRefundPolicyResult {
  if (!validationResult?.request_validated) {
    throw new PermanentError('Request validation must be completed before policy check');
  }

  const customerTier = (validationResult.customer_tier as string) || 'standard';
  const purchaseDateStr = validationResult.original_purchase_date as string;

  const policy = REFUND_POLICIES[customerTier] || REFUND_POLICIES.standard;
  const purchaseDate = new Date(purchaseDateStr);
  const daysSincePurchase = Math.floor(
    (Date.now() - purchaseDate.getTime()) / (24 * 60 * 60 * 1000),
  );
  const withinWindow = daysSincePurchase <= policy.window_days;

  const now = new Date().toISOString();

  return {
    policy_checked: true,
    policy_compliant: true,
    customer_tier: customerTier,
    refund_window_days: policy.window_days,
    days_since_purchase: daysSincePurchase,
    within_refund_window: withinWindow,
    requires_approval: policy.requires_approval,
    max_allowed_amount: policy.max_amount,
    policy_checked_at: now,
    namespace: 'customer_success_ts',
  };
}

export function calculateRefundAmount(
  policyResult: Record<string, unknown>,
  customerId: string | undefined,
): CustomerSuccessApproveRefundResult {
  if (!policyResult?.policy_checked) {
    throw new PermanentError('Policy check must be completed before approval');
  }

  const requiresApproval = policyResult.requires_approval as boolean;
  const customerTier = policyResult.customer_tier as string;
  const now = new Date().toISOString();

  if (requiresApproval) {
    return {
      approval_obtained: true,
      approval_required: true,
      auto_approved: false,
      approval_id: `appr_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
      manager_id: `mgr_${Math.floor(Math.random() * 5) + 1}`,
      manager_notes: `Approved refund request for customer ${customerId}`,
      approved_at: now,
      namespace: 'customer_success_ts',
    };
  } else {
    return {
      approval_obtained: true,
      approval_required: false,
      auto_approved: true,
      approval_id: null,
      manager_id: null,
      manager_notes: `Auto-approved for customer tier ${customerTier}`,
      approved_at: now,
      namespace: 'customer_success_ts',
    };
  }
}

export function notifyCustomerSuccess(
  approvalResult: Record<string, unknown>,
  validationResult: Record<string, unknown>,
  correlationId: string | undefined,
): CustomerSuccessExecuteRefundResult {
  if (!approvalResult?.approval_obtained) {
    throw new PermanentError('Manager approval must be obtained before executing refund');
  }

  const paymentId = validationResult?.payment_id as string;
  if (!paymentId) {
    throw new PermanentError('Payment ID not found in validation results');
  }

  correlationId = correlationId || `cs-corr_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`;

  const taskId = `task_${crypto.randomUUID()}`;
  const now = new Date().toISOString();

  return {
    task_delegated: true,
    target_namespace: 'payments_ts',
    target_workflow: 'process_refund',
    delegated_task_id: taskId,
    delegated_task_status: 'created',
    delegation_timestamp: now,
    correlation_id: correlationId,
    namespace: 'customer_success_ts',
  };
}

export function updateCrmRecord(
  delegationResult: Record<string, unknown>,
  validationResult: Record<string, unknown>,
  refundAmount: number | undefined,
): CustomerSuccessUpdateTicketResult {
  if (!delegationResult?.task_delegated) {
    throw new PermanentError('Refund workflow must be executed before updating ticket');
  }

  const ticketId = validationResult?.ticket_id as string;
  const delegatedTaskId = delegationResult.delegated_task_id as string;
  const correlationId = delegationResult.correlation_id as string;

  const now = new Date().toISOString();

  return {
    ticket_updated: true,
    ticket_id: ticketId,
    previous_status: 'in_progress',
    new_status: 'resolved',
    resolution_note: `Refund of $${(refundAmount! / 100).toFixed(2)} processed successfully. Delegated task ID: ${delegatedTaskId}. Correlation ID: ${correlationId}`,
    updated_at: now,
    refund_completed: true,
    delegated_task_id: delegatedTaskId,
    namespace: 'customer_success_ts',
  };
}
