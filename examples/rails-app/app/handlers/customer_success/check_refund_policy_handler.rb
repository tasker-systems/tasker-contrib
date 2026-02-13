module CustomerSuccess
  module StepHandlers
    class CheckRefundPolicyHandler < TaskerCore::StepHandler::Base
      REFUND_WINDOW_DAYS = 30
      NO_QUESTIONS_THRESHOLD = 25.00
      MAX_REFUNDS_PER_CUSTOMER = 5

      # Reason-specific policies
      REASON_POLICIES = {
        'defective'        => { window_days: 90, auto_approve_threshold: 500.00 },
        'not_as_described' => { window_days: 60, auto_approve_threshold: 200.00 },
        'changed_mind'     => { window_days: 30, auto_approve_threshold: 50.00 },
        'late_delivery'    => { window_days: 45, auto_approve_threshold: 100.00 },
        'duplicate_charge' => { window_days: 180, auto_approve_threshold: Float::INFINITY }
      }.freeze

      def call(context)
        validation = context.get_dependency_field('validate_refund_request', ['result'])

        raise TaskerCore::Errors::PermanentError.new(
          'Validation data not available',
          error_code: 'MISSING_VALIDATION'
        ) if validation.nil?

        reason = validation['reason']
        amount = validation['refund_amount'].to_f
        order_data = validation['order_data'] || {}
        order_date = Date.parse(order_data['order_date'] || Date.current.iso8601)
        previous_refunds = order_data['previous_refunds'].to_i
        customer_tier = order_data['customer_tier'] || 'standard'

        policy = REASON_POLICIES[reason] || { window_days: REFUND_WINDOW_DAYS, auto_approve_threshold: 0 }
        days_since_order = (Date.current - order_date).to_i

        # Policy checks
        violations = []
        warnings = []

        if days_since_order > policy[:window_days]
          violations << "Order is #{days_since_order} days old, exceeding #{policy[:window_days]}-day window for '#{reason}'"
        end

        if previous_refunds >= MAX_REFUNDS_PER_CUSTOMER
          violations << "Customer has #{previous_refunds} previous refunds, exceeding limit of #{MAX_REFUNDS_PER_CUSTOMER}"
        end

        if previous_refunds >= 3
          warnings << "Customer has #{previous_refunds} previous refunds - flagged for review"
        end

        # VIP customers get extended windows
        if customer_tier == 'vip' && violations.any? { |v| v.include?('window') }
          violations.reject! { |v| v.include?('window') }
          warnings << 'VIP customer - refund window policy waived'
        end

        policy_passed = violations.empty?

        # Determine approval requirements
        auto_approve = policy_passed && amount <= policy[:auto_approve_threshold]
        requires_manager = !auto_approve && amount > 100.00
        approval_level = if auto_approve
                           'auto'
                         elsif requires_manager
                           amount > 1000.00 ? 'senior_manager' : 'manager'
                         else
                           'agent'
                         end

        check_id = "pol_#{SecureRandom.hex(8)}"

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            check_id: check_id,
            policy_passed: policy_passed,
            violations: violations,
            warnings: warnings,
            auto_approve: auto_approve,
            requires_manager_approval: requires_manager,
            approval_level: approval_level,
            applied_policy: {
              reason: reason,
              window_days: policy[:window_days],
              auto_approve_threshold: policy[:auto_approve_threshold] == Float::INFINITY ? 'unlimited' : policy[:auto_approve_threshold],
              days_since_order: days_since_order,
              customer_tier: customer_tier
            },
            checked_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            check_id: check_id,
            policy_passed: policy_passed,
            approval_level: approval_level,
            violation_count: violations.size
          }
        )
      end
    end
  end
end
