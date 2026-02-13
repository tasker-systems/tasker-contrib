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
      const orderId = context.getInput<string>('order_id');
      const customerEmail = context.getInput<string>('customer_email');
      const refundReason = context.getInput<string>('refund_reason') || 'Customer request';

      if (!orderId) {
        return this.failure(
          'order_id is required for refund validation',
          ErrorType.VALIDATION_ERROR,
          false,
        );
      }

      if (!customerEmail) {
        return this.failure(
          'customer_email is required for refund validation',
          ErrorType.VALIDATION_ERROR,
          false,
        );
      }

      // Simulate order lookup and validation
      const orderAge = Math.floor(Math.random() * 60) + 1; // days since purchase
      const refundWindow = 30; // 30-day refund window
      const withinRefundWindow = orderAge <= refundWindow;

      // Validate refund reason categories
      const validReasons = [
        'defective_product',
        'wrong_item',
        'not_as_described',
        'changed_mind',
        'duplicate_order',
        'customer_request',
        'late_delivery',
      ];
      const normalizedReason = refundReason.toLowerCase().replace(/\s+/g, '_');
      const isValidReason = validReasons.includes(normalizedReason);

      const requestId = `RFD-${Date.now()}-${Math.random().toString(36).substring(2, 6).toUpperCase()}`;

      return this.success(
        {
          request_id: requestId,
          order_id: orderId,
          customer_email: customerEmail,
          refund_reason: normalizedReason,
          is_valid_reason: isValidReason,
          order_age_days: orderAge,
          within_refund_window: withinRefundWindow,
          validation_status: withinRefundWindow && isValidReason ? 'approved' : 'requires_review',
          policy_version: '2024.1',
          validated_at: new Date().toISOString(),
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
  static handlerName = 'CustomerSuccess.StepHandlers.CheckRefundEligibilityHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const validationResult = context.getDependencyResult('validate_refund_request') as Record<string, unknown>;

      if (!validationResult) {
        return this.failure('Missing refund validation result', ErrorType.HANDLER_ERROR, true);
      }

      const customerEmail = validationResult.customer_email as string;
      const withinWindow = validationResult.within_refund_window as boolean;
      const validReason = validationResult.is_valid_reason as boolean;

      // Simulate customer history lookup
      const previousRefunds = Math.floor(Math.random() * 5);
      const accountAge = Math.floor(Math.random() * 365) + 30; // days
      const totalOrders = Math.floor(Math.random() * 20) + 1;
      const customerTier = totalOrders > 10 ? 'gold' : totalOrders > 5 ? 'silver' : 'bronze';

      // Calculate eligibility score (0-100)
      let eligibilityScore = 100;
      if (!withinWindow) eligibilityScore -= 40;
      if (!validReason) eligibilityScore -= 20;
      if (previousRefunds > 3) eligibilityScore -= 15 * (previousRefunds - 3);
      if (accountAge < 90) eligibilityScore -= 10;
      eligibilityScore = Math.max(0, Math.min(100, eligibilityScore));

      const eligible = eligibilityScore >= 50;
      const requiresApproval = eligibilityScore >= 50 && eligibilityScore < 75;

      return this.success(
        {
          customer_email: customerEmail,
          eligible,
          eligibility_score: eligibilityScore,
          requires_manual_approval: requiresApproval,
          customer_profile: {
            tier: customerTier,
            account_age_days: accountAge,
            total_orders: totalOrders,
            previous_refunds: previousRefunds,
            lifetime_value: Math.round((totalOrders * 85 + Math.random() * 500) * 100) / 100,
          },
          decision_factors: {
            within_refund_window: withinWindow,
            valid_reason: validReason,
            refund_history_ok: previousRefunds <= 3,
            account_age_ok: accountAge >= 90,
          },
          checked_at: new Date().toISOString(),
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
  static handlerName = 'CustomerSuccess.StepHandlers.CalculateRefundAmountHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const eligibilityResult = context.getDependencyResult('check_refund_eligibility') as Record<string, unknown>;
      const validationResult = context.getDependencyResult('validate_refund_request') as Record<string, unknown>;

      if (!eligibilityResult || !validationResult) {
        return this.failure('Missing dependency results', ErrorType.HANDLER_ERROR, true);
      }

      const eligible = eligibilityResult.eligible as boolean;

      if (!eligible) {
        return this.success(
          {
            refund_amount: 0,
            original_amount: 0,
            refund_type: 'none',
            reason: 'Customer not eligible for refund',
            eligible: false,
          },
          { calculation_time_ms: 5 },
        );
      }

      // Simulate order amount calculation
      const originalAmount = Math.round((Math.random() * 200 + 20) * 100) / 100;
      const reason = validationResult.refund_reason as string;
      const profile = eligibilityResult.customer_profile as Record<string, unknown>;
      const tier = profile.tier as string;

      // Calculate refund based on reason and tier
      let refundPercentage = 100;
      let restockingFee = 0;

      if (reason === 'changed_mind') {
        restockingFee = Math.round(originalAmount * 0.15 * 100) / 100; // 15% restocking
        refundPercentage = 85;
      } else if (reason === 'late_delivery') {
        refundPercentage = 100; // Full refund for late delivery
      }

      // Loyalty bonus: gold tier customers get full refunds
      if (tier === 'gold' && refundPercentage < 100) {
        refundPercentage = 100;
        restockingFee = 0;
      }

      const refundAmount = Math.round(originalAmount * (refundPercentage / 100) * 100) / 100;

      return this.success(
        {
          original_amount: originalAmount,
          refund_amount: refundAmount,
          restocking_fee: restockingFee,
          refund_percentage: refundPercentage,
          refund_type: refundAmount === originalAmount ? 'full' : 'partial',
          currency: 'usd',
          loyalty_adjustment: tier === 'gold' && reason === 'changed_mind',
          breakdown: {
            product_refund: refundAmount,
            tax_refund: Math.round(refundAmount * 0.0875 * 100) / 100,
            shipping_refund: reason === 'defective_product' ? 9.99 : 0,
          },
          eligible: true,
          calculated_at: new Date().toISOString(),
        },
        { calculation_time_ms: Math.random() * 40 + 10 },
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
// Step 4: NotifyCustomerSuccess (depends on CalculateRefundAmount)
// ---------------------------------------------------------------------------

export class NotifyCustomerSuccessHandler extends StepHandler {
  static handlerName = 'CustomerSuccess.StepHandlers.NotifyCustomerSuccessHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const validationResult = context.getDependencyResult('validate_refund_request') as Record<string, unknown>;
      const eligibilityResult = context.getDependencyResult('check_refund_eligibility') as Record<string, unknown>;
      const calculationResult = context.getDependencyResult('calculate_refund_amount') as Record<string, unknown>;

      if (!validationResult || !eligibilityResult || !calculationResult) {
        return this.failure('Missing dependency results', ErrorType.HANDLER_ERROR, true);
      }

      const customerEmail = validationResult.customer_email as string;
      const requestId = validationResult.request_id as string;
      const refundAmount = calculationResult.refund_amount as number;
      const eligible = calculationResult.eligible as boolean;

      // Determine notification template and channels
      const template = eligible ? 'refund_approved_v2' : 'refund_denied_v2';
      const subject = eligible
        ? `Your refund of $${refundAmount.toFixed(2)} has been approved`
        : 'Update on your refund request';

      const notifications = [
        {
          channel: 'email',
          recipient: customerEmail,
          template,
          subject,
          message_id: crypto.randomUUID(),
          status: 'queued',
        },
        {
          channel: 'in_app',
          recipient: customerEmail,
          template: `${template}_in_app`,
          message_id: crypto.randomUUID(),
          status: 'delivered',
        },
      ];

      // Notify CS team via internal channel for high-value refunds
      if (refundAmount > 100) {
        notifications.push({
          channel: 'slack',
          recipient: '#cs-refunds',
          template: 'cs_team_refund_alert',
          subject: `High-value refund: ${requestId} - $${refundAmount.toFixed(2)}`,
          message_id: crypto.randomUUID(),
          status: 'queued',
        });
      }

      return this.success(
        {
          request_id: requestId,
          notifications,
          notification_count: notifications.length,
          customer_notified: true,
          team_notified: refundAmount > 100,
          csat_survey_scheduled: eligible,
          follow_up_date: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
          notified_at: new Date().toISOString(),
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
  static handlerName = 'CustomerSuccess.StepHandlers.UpdateCrmRecordHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const validationResult = context.getDependencyResult('validate_refund_request') as Record<string, unknown>;
      const eligibilityResult = context.getDependencyResult('check_refund_eligibility') as Record<string, unknown>;
      const calculationResult = context.getDependencyResult('calculate_refund_amount') as Record<string, unknown>;
      const notificationResult = context.getDependencyResult('notify_customer_success') as Record<string, unknown>;

      if (!validationResult || !eligibilityResult || !calculationResult || !notificationResult) {
        return this.failure('Missing dependency results', ErrorType.HANDLER_ERROR, true);
      }

      const customerEmail = validationResult.customer_email as string;
      const orderId = validationResult.order_id as string;
      const requestId = validationResult.request_id as string;
      const profile = eligibilityResult.customer_profile as Record<string, unknown>;
      const refundAmount = calculationResult.refund_amount as number;

      // Simulate CRM record update
      const crmRecordId = `CRM-${crypto.randomUUID().substring(0, 8)}`;
      const caseId = `CASE-${Date.now()}-${Math.random().toString(36).substring(2, 5).toUpperCase()}`;

      const crmUpdates = [
        { field: 'last_interaction', value: new Date().toISOString(), updated: true },
        { field: 'refund_history', value: `Added ${requestId}`, updated: true },
        { field: 'satisfaction_risk', value: refundAmount > 100 ? 'medium' : 'low', updated: true },
        { field: 'retention_score', value: Math.max(0, (profile.lifetime_value as number) - refundAmount), updated: true },
      ];

      return this.success(
        {
          crm_record_id: crmRecordId,
          case_id: caseId,
          customer_email: customerEmail,
          order_id: orderId,
          request_id: requestId,
          updates_applied: crmUpdates,
          fields_updated: crmUpdates.length,
          case_status: 'resolved',
          resolution_type: calculationResult.eligible ? 'refund_issued' : 'refund_denied',
          resolution_summary: {
            refund_amount: refundAmount,
            customer_tier: profile.tier,
            notifications_sent: notificationResult.notification_count,
          },
          crm_provider: 'salesforce_simulator',
          updated_at: new Date().toISOString(),
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
