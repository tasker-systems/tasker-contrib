import {
  StepHandler,
  type StepContext,
  type StepHandlerResult,
  ErrorType,
} from '@tasker-systems/tasker';

// ---------------------------------------------------------------------------
// Customer Success Namespace - Refund Processing (5 steps)
// Demonstrates namespace isolation in the team scaling pattern.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Step 1: ValidateRefundRequest
// ---------------------------------------------------------------------------

export class ValidateRefundRequestHandler extends StepHandler {
  static handlerName = 'CustomerSuccess.StepHandlers.ValidateRefundRequestHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      // TAS-137: Use getInput() for task context access (matches source key names)
      const ticketId = context.getInput('ticket_id') as string | undefined;
      const customerId = context.getInput('customer_id') as string | undefined;
      const refundAmount = context.getInput('refund_amount') as number | undefined;
      const _refundReason = context.getInput('refund_reason') as string | undefined;

      // Validate required fields
      const missingFields: string[] = [];
      if (!ticketId) missingFields.push('ticket_id');
      if (!customerId) missingFields.push('customer_id');
      if (!refundAmount) missingFields.push('refund_amount');

      if (missingFields.length > 0) {
        return this.failure(
          `Missing required fields for refund validation: ${missingFields.join(', ')}`,
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      // Simulate customer service system validation
      const purchaseDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

      // Determine customer tier
      let customerTier = 'standard';
      if (customerId!.toLowerCase().includes('vip') || customerId!.toLowerCase().includes('premium')) {
        customerTier = 'premium';
      } else if (customerId!.toLowerCase().includes('gold')) {
        customerTier = 'gold';
      }

      const now = new Date().toISOString();

      return this.success(
        {
          request_validated: true,
          ticket_id: ticketId,
          customer_id: customerId,
          ticket_status: 'open',
          customer_tier: customerTier,
          original_purchase_date: purchaseDate,
          payment_id: `pay_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
          validation_timestamp: now,
          namespace: 'customer_success',
        },
        { validation_time_ms: Math.random() * 80 + 20 },
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
// Step 2: CheckRefundEligibility (depends on ValidateRefundRequest)
// ---------------------------------------------------------------------------

export class CheckRefundEligibilityHandler extends StepHandler {
  static handlerName = 'CustomerSuccess.StepHandlers.CheckRefundPolicyHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const validationResult = context.getDependencyResult('validate_refund_request') as Record<string, unknown>;

      if (!validationResult?.request_validated) {
        return this.failure(
          'Request validation must be completed before policy check',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      // Read keys matching source (customer_tier, original_purchase_date from dependency)
      const customerTier = (validationResult.customer_tier as string) || 'standard';
      const purchaseDateStr = validationResult.original_purchase_date as string;
      const refundAmount = context.getInput('refund_amount') as number;

      // Refund policy rules by customer tier
      const refundPolicies: Record<string, { window_days: number; requires_approval: boolean; max_amount: number }> = {
        standard: { window_days: 30, requires_approval: true, max_amount: 10_000 },
        gold: { window_days: 60, requires_approval: false, max_amount: 50_000 },
        premium: { window_days: 90, requires_approval: false, max_amount: 100_000 },
      };

      const policy = refundPolicies[customerTier] || refundPolicies.standard;
      const purchaseDate = new Date(purchaseDateStr);
      const daysSincePurchase = Math.floor(
        (Date.now() - purchaseDate.getTime()) / (24 * 60 * 60 * 1000),
      );
      const withinWindow = daysSincePurchase <= policy.window_days;

      const now = new Date().toISOString();

      return this.success(
        {
          policy_checked: true,
          policy_compliant: true,
          customer_tier: customerTier,
          refund_window_days: policy.window_days,
          days_since_purchase: daysSincePurchase,
          within_refund_window: withinWindow,
          requires_approval: policy.requires_approval,
          max_allowed_amount: policy.max_amount,
          policy_checked_at: now,
          namespace: 'customer_success',
        },
        { eligibility_check_ms: Math.random() * 120 + 30 },
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
// Step 3: CalculateRefundAmount (depends on CheckRefundEligibility)
// ---------------------------------------------------------------------------

export class CalculateRefundAmountHandler extends StepHandler {
  static handlerName = 'CustomerSuccess.StepHandlers.GetManagerApprovalHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      // TAS-137: Read dependency results matching source key names
      const policyResult = context.getDependencyResult('check_refund_policy') as Record<string, unknown>;

      if (!policyResult?.policy_checked) {
        return this.failure(
          'Policy check must be completed before approval',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const requiresApproval = policyResult.requires_approval as boolean;
      const customerTier = policyResult.customer_tier as string;
      const customerId = (context.getDependencyResult('validate_refund_request') as Record<string, unknown>)?.customer_id as string;

      const now = new Date().toISOString();

      if (requiresApproval) {
        // Approval granted (simulated)
        return this.success(
          {
            approval_obtained: true,
            approval_required: true,
            auto_approved: false,
            approval_id: `appr_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
            manager_id: `mgr_${Math.floor(Math.random() * 5) + 1}`,
            manager_notes: `Approved refund request for customer ${customerId}`,
            approved_at: now,
            namespace: 'customer_success',
          },
          { calculation_time_ms: Math.random() * 40 + 10 },
        );
      } else {
        // Auto-approved
        return this.success(
          {
            approval_obtained: true,
            approval_required: false,
            auto_approved: true,
            approval_id: null,
            manager_id: null,
            manager_notes: `Auto-approved for customer tier ${customerTier}`,
            approved_at: now,
            namespace: 'customer_success',
          },
          { calculation_time_ms: Math.random() * 40 + 10 },
        );
      }
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
// Step 4: NotifyCustomerSuccess (depends on CalculateRefundAmount)
// ---------------------------------------------------------------------------

export class NotifyCustomerSuccessHandler extends StepHandler {
  static handlerName = 'CustomerSuccess.StepHandlers.ExecuteRefundWorkflowHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      // TAS-137: Read dependency results matching source key names
      const approvalResult = context.getDependencyResult('get_manager_approval') as Record<string, unknown>;

      if (!approvalResult?.approval_obtained) {
        return this.failure(
          'Manager approval must be obtained before executing refund',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const validationResult = context.getDependencyResult('validate_refund_request') as Record<string, unknown>;
      const paymentId = validationResult?.payment_id as string;
      if (!paymentId) {
        return this.failure(
          'Payment ID not found in validation results',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const correlationId =
        (context.getInput('correlation_id') as string) || `cs-corr_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`;

      // Simulate task creation in payments namespace
      const taskId = `task_${crypto.randomUUID()}`;
      const now = new Date().toISOString();

      return this.success(
        {
          task_delegated: true,
          target_namespace: 'payments',
          target_workflow: 'process_refund',
          delegated_task_id: taskId,
          delegated_task_status: 'created',
          delegation_timestamp: now,
          correlation_id: correlationId,
          namespace: 'customer_success',
        },
        { notification_dispatch_ms: Math.random() * 100 + 30 },
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
// Step 5: UpdateCrmRecord (depends on NotifyCustomerSuccess -- final step)
// ---------------------------------------------------------------------------

export class UpdateCrmRecordHandler extends StepHandler {
  static handlerName = 'CustomerSuccess.StepHandlers.UpdateTicketStatusHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      // TAS-137: Read dependency results matching source key names
      const delegationResult = context.getDependencyResult('execute_refund_workflow') as Record<string, unknown>;

      if (!delegationResult?.task_delegated) {
        return this.failure(
          'Refund workflow must be executed before updating ticket',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const validationResult = context.getDependencyResult('validate_refund_request') as Record<string, unknown>;
      const ticketId = validationResult?.ticket_id as string;
      const delegatedTaskId = delegationResult.delegated_task_id as string;
      const correlationId = delegationResult.correlation_id as string;
      const refundAmount = context.getInput('refund_amount') as number;

      const now = new Date().toISOString();

      return this.success(
        {
          ticket_updated: true,
          ticket_id: ticketId,
          previous_status: 'in_progress',
          new_status: 'resolved',
          resolution_note: `Refund of $${(refundAmount / 100).toFixed(2)} processed successfully. Delegated task ID: ${delegatedTaskId}. Correlation ID: ${correlationId}`,
          updated_at: now,
          refund_completed: true,
          delegated_task_id: delegatedTaskId,
          namespace: 'customer_success',
        },
        { crm_update_ms: Math.random() * 150 + 40 },
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
