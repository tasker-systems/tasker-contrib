# frozen_string_literal: true

# Service functions return Dry::Struct instances from Types::CustomerSuccess.
# See Types::CustomerSuccess in app/services/types.rb for full struct definitions.
#   validate_refund_request     -> Types::CustomerSuccess::ValidateRefundResult
#   check_refund_policy         -> Types::CustomerSuccess::CheckPolicyResult
#   get_manager_approval        -> Types::CustomerSuccess::ApproveRefundResult
#   execute_refund_workflow     -> Types::CustomerSuccess::ExecuteRefundResult
#   update_ticket_status        -> Types::CustomerSuccess::UpdateTicketResult
module CustomerSuccess
  module Service
    VALID_REASONS = %w[defective not_as_described changed_mind late_delivery duplicate_charge].freeze
    NO_QUESTIONS_THRESHOLD = 25.00
    MAX_REFUNDS_PER_CUSTOMER = 5

    REASON_POLICIES = {
      'defective' => { window_days: 90, auto_approve_threshold: 500.00 },
      'not_as_described' => { window_days: 60, auto_approve_threshold: 200.00 },
      'changed_mind' => { window_days: 30, auto_approve_threshold: 50.00 },
      'late_delivery' => { window_days: 45, auto_approve_threshold: 100.00 },
      'duplicate_charge' => { window_days: 180, auto_approve_threshold: Float::INFINITY }
    }.freeze

    REFUND_WINDOW_DAYS = 30

    module_function

    def validate_refund_request(input:)
      amount = input.refund_amount.to_f
      ticket_id = input.ticket_id
      order_ref = input.order_ref
      customer_id = input.customer_id
      refund_reason = input.resolved_refund_reason
      if amount <= 0
        raise TaskerCore::Errors::PermanentError.new(
          "Invalid refund amount: #{amount}. Must be greater than 0",
          error_code: 'INVALID_AMOUNT'
        )
      end

      if amount > 10_000
        raise TaskerCore::Errors::PermanentError.new(
          "Invalid refund amount: #{amount}. Maximum single refund is $10,000",
          error_code: 'AMOUNT_EXCEEDS_LIMIT'
        )
      end

      unless VALID_REASONS.include?(refund_reason)
        raise TaskerCore::Errors::PermanentError.new(
          "Invalid reason: #{refund_reason}. Must be one of: #{VALID_REASONS.join(', ')}",
          error_code: 'INVALID_REASON'
        )
      end

      # Simulate order lookup
      order_data = {
        order_ref: order_ref,
        original_amount: (amount + rand(0.0..50.0)).round(2),
        order_date: (Date.current - rand(1..90)).iso8601,
        items_count: rand(1..5),
        payment_method: %w[credit_card debit_card paypal].sample,
        previous_refunds: rand(0..2),
        customer_tier: %w[standard premium vip].sample
      }

      validation_id = "val_#{SecureRandom.hex(8)}"
      customer_tier = order_data[:customer_tier]

      Types::CustomerSuccess::ValidateRefundResult.new(
        request_validated: true,
        ticket_id: ticket_id,
        customer_id: customer_id,
        ticket_status: 'open',
        customer_tier: customer_tier,
        original_purchase_date: order_data[:order_date],
        payment_id: "pay_#{SecureRandom.hex(8)}",
        validation_timestamp: Time.current.iso8601,
        namespace: 'customer_success_rb',
        validation_id: validation_id,
        order_ref: order_ref,
        refund_amount: amount,
        reason: refund_reason,
        order_data: order_data,
        refund_percentage: ((amount / order_data[:original_amount]) * 100).round(1),
        is_partial_refund: amount < order_data[:original_amount],
        is_valid: true,
        validated_at: Time.current.iso8601
      )
    end

    def check_refund_policy(validation:)
      if validation.nil?
        raise TaskerCore::Errors::PermanentError.new(
          'Validation data not available',
          error_code: 'MISSING_VALIDATION'
        )
      end

      reason = validation['reason']
      amount = validation['refund_amount'].to_f
      order_data = validation['order_data'] || {}
      order_date = Date.parse(order_data['order_date'] || Date.current.iso8601)
      previous_refunds = order_data['previous_refunds'].to_i
      customer_tier = validation['customer_tier'] || order_data['customer_tier'] || 'standard'

      policy = REASON_POLICIES[reason] || { window_days: REFUND_WINDOW_DAYS, auto_approve_threshold: 0.0 }
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

      warnings << "Customer has #{previous_refunds} previous refunds - flagged for review" if previous_refunds >= 3

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

      Types::CustomerSuccess::CheckPolicyResult.new(
        policy_checked: true,
        policy_compliant: policy_passed,
        customer_tier: customer_tier,
        refund_window_days: policy[:window_days],
        days_since_purchase: days_since_order,
        within_refund_window: days_since_order <= policy[:window_days],
        requires_approval: requires_manager,
        max_allowed_amount: (policy[:auto_approve_threshold] == Float::INFINITY ? 999_999.0 : policy[:auto_approve_threshold]).to_f,
        policy_checked_at: Time.current.iso8601,
        namespace: 'customer_success_rb',
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
      )
    end

    def get_manager_approval(validation:, policy_check:)
      if validation.nil? || policy_check.nil?
        raise TaskerCore::Errors::PermanentError.new(
          'Upstream data not available for approval routing',
          error_code: 'MISSING_DEPENDENCIES'
        )
      end

      customer_id_field = validation['customer_id']

      # If policy check failed, deny immediately
      unless policy_check['policy_passed']
        return Types::CustomerSuccess::ApproveRefundResult.new(
          approval_obtained: false,
          approval_required: false,
          auto_approved: false,
          approval_id: "apr_#{SecureRandom.hex(8)}",
          manager_id: nil,
          manager_notes: nil,
          approved_at: Time.current.iso8601,
          namespace: 'customer_success_rb',
          approved: false,
          reason: 'policy_violation',
          decision_type: 'automatic',
          decided_by: 'system',
          decided_at: Time.current.iso8601
        )
      end

      # If auto-approved, no manager needed
      if policy_check['auto_approve']
        return Types::CustomerSuccess::ApproveRefundResult.new(
          approval_obtained: true,
          approval_required: false,
          auto_approved: true,
          approval_id: "apr_#{SecureRandom.hex(8)}",
          manager_id: nil,
          manager_notes: nil,
          approved_at: Time.current.iso8601,
          namespace: 'customer_success_rb',
          approved: true,
          reason: 'auto_approved',
          approval_level: 'auto',
          decision_type: 'automatic',
          decided_by: 'system',
          conditions: [],
          decided_at: Time.current.iso8601
        )
      end

      # Simulate manager review
      approval_level = policy_check['approval_level']
      amount = validation['refund_amount'].to_f
      approval_id = "apr_#{SecureRandom.hex(8)}"

      manager = case approval_level
                when 'senior_manager'
                  { id: "mgr_#{SecureRandom.hex(6)}", name: 'Senior Operations Manager', level: 'senior' }
                else
                  { id: "mgr_#{SecureRandom.hex(6)}", name: 'Team Lead', level: 'standard' }
                end

      approved = rand < 0.85
      conditions = []

      conditions << 'Customer must return defective items within 14 days' if approved && amount > 500

      conditions << 'Flag customer account for monitoring' if approved && validation.dig('order_data', 'previous_refunds').to_i > 1

      rand(5..120)

      Types::CustomerSuccess::ApproveRefundResult.new(
        approval_obtained: approved,
        approval_required: true,
        auto_approved: false,
        approval_id: approval_id,
        manager_id: manager[:id],
        manager_notes: approved ? "Approved refund request for customer #{customer_id_field}" : 'Refund request does not meet approval criteria after review',
        approved_at: Time.current.iso8601,
        namespace: 'customer_success_rb',
        approved: approved,
        reason: approved ? 'manager_approved' : 'manager_denied',
        denial_reason: approved ? nil : 'Refund request does not meet approval criteria after review',
        approval_level: approval_level,
        decision_type: 'manual',
        decided_by: manager[:id],
        manager: manager,
        requesting_agent: 'unassigned',
        priority: 'normal',
        conditions: conditions,
        decided_at: Time.current.iso8601
      )
    end

    def execute_refund_workflow(validation:, approval:, correlation_id: nil)
      if validation.nil? || approval.nil?
        raise TaskerCore::Errors::PermanentError.new(
          'Upstream data not available for refund execution',
          error_code: 'MISSING_DEPENDENCIES'
        )
      end

      unless approval['approved'] || approval['approval_obtained']
        raise TaskerCore::Errors::PermanentError.new(
          'Manager approval must be obtained before executing refund',
          error_code: 'MISSING_APPROVAL'
        )
      end

      amount = validation['refund_amount'].to_f
      order_ref = validation['order_ref']
      customer_id = validation['customer_id']
      payment_method = validation.dig('order_data', 'payment_method') || 'unknown'

      delegated_task_id = "task_#{SecureRandom.uuid}"
      correlation_id ||= "cs-#{SecureRandom.hex(8)}"

      execution_id = "exec_#{SecureRandom.hex(8)}"
      refund_transaction_id = "rfnd_#{SecureRandom.hex(12)}"

      steps_executed = []

      steps_executed << {
        step: 'initiate_refund',
        status: 'completed',
        transaction_id: refund_transaction_id,
        amount: amount,
        payment_method: payment_method,
        completed_at: Time.current.iso8601
      }

      steps_executed << {
        step: 'update_order',
        status: 'completed',
        order_ref: order_ref,
        new_status: 'refunded',
        completed_at: Time.current.iso8601
      }

      if %w[defective not_as_described].include?(validation['reason'])
        return_label = "RMA-#{SecureRandom.hex(6).upcase}"
        steps_executed << {
          step: 'create_return_label',
          status: 'completed',
          return_label: return_label,
          carrier: 'USPS',
          completed_at: Time.current.iso8601
        }
      end

      steps_executed << {
        step: 'credit_account',
        status: 'completed',
        customer_id: customer_id,
        credit_amount: amount,
        estimated_arrival: begin
          Time.current + 5.business_days
        rescue StandardError
          Time.current + 7.days
        end.iso8601,
        completed_at: Time.current.iso8601
      }

      points_deducted = (amount * 10).round(0)
      steps_executed << {
        step: 'adjust_loyalty_points',
        status: 'completed',
        points_deducted: points_deducted,
        completed_at: Time.current.iso8601
      }

      all_completed = steps_executed.all? { |s| s[:status] == 'completed' }

      Types::CustomerSuccess::ExecuteRefundResult.new(
        task_delegated: true,
        target_namespace: 'payments_rb',
        target_workflow: 'process_refund',
        delegated_task_id: delegated_task_id,
        delegated_task_status: 'created',
        delegation_timestamp: Time.current.iso8601,
        correlation_id: correlation_id,
        namespace: 'customer_success_rb',
        execution_id: execution_id,
        executed: all_completed,
        refund_transaction_id: refund_transaction_id,
        amount_refunded: amount,
        order_ref: order_ref,
        customer_id: customer_id,
        payment_method: payment_method,
        steps_executed: steps_executed,
        total_steps: steps_executed.size,
        all_steps_completed: all_completed,
        conditions_applied: approval['conditions'] || [],
        executed_at: Time.current.iso8601
      )
    end

    def update_ticket_status(validation:, policy_check:, approval:, execution:)
      if validation.nil? || execution.nil?
        raise TaskerCore::Errors::PermanentError.new(
          'Upstream data not available for ticket update',
          error_code: 'MISSING_DEPENDENCIES'
        )
      end

      ticket_id = validation['ticket_id']
      validation['customer_id']
      delegated_task_id = execution['delegated_task_id']
      correlation_id = execution['correlation_id']

      was_approved = approval&.dig('approved') == true
      was_executed = execution&.dig('executed') == true || execution&.dig('task_delegated') == true

      ticket_status = if was_executed
                        'resolved_refunded'
                      elsif was_approved && !was_executed
                        'resolved_execution_failed'
                      elsif !was_approved && (policy_check&.dig('policy_passed') == false)
                        'resolved_policy_denied'
                      elsif !was_approved
                        'resolved_manager_denied'
                      else
                        'resolved_unknown'
                      end

      resolution_category = case ticket_status
                            when 'resolved_refunded' then 'refund_processed'
                            when /denied/ then 'refund_denied'
                            else 'refund_failed'
                            end

      timeline = [
        { event: 'ticket_opened', timestamp: validation['validated_at'] },
        { event: 'request_validated', timestamp: validation['validated_at'] }
      ]

      if policy_check
        timeline << { event: 'policy_checked', result: policy_check['policy_passed'] ? 'passed' : 'failed',
                      timestamp: policy_check['checked_at'] }
      end

      if approval
        timeline << { event: 'approval_decision', result: approval['approved'] ? 'approved' : 'denied',
                      timestamp: approval['decided_at'] }
      end

      if execution
        timeline << { event: 'refund_execution', result: was_executed ? 'completed' : 'skipped',
                      timestamp: execution['executed_at'] || execution['delegation_timestamp'] }
      end

      timeline << { event: 'ticket_closed', result: ticket_status, timestamp: Time.current.iso8601 }

      resolution_note = "Refund of $#{format('%.2f',
                                             validation['refund_amount'].to_f)} for order #{validation['order_ref']}. " \
                       "Reason: #{validation['reason']}. " \
                       "Delegated task ID: #{delegated_task_id}. " \
                       "Correlation ID: #{correlation_id}"

      notes = []
      notes << "Refund of $#{format('%.2f', validation['refund_amount'].to_f)} for order #{validation['order_ref']}"
      notes << "Reason: #{validation['reason']}"
      notes << "Policy: #{policy_check&.dig('policy_passed') ? 'Passed' : 'Failed'}"
      notes << "Approval: #{approval&.dig('approval_level') || 'N/A'} - #{approval&.dig('approved') ? 'Approved' : 'Denied'}"
      notes << "Execution: #{was_executed ? 'Completed' : 'Not executed'}"

      if (conditions = approval&.dig('conditions')) && conditions.any?
        notes << "Conditions: #{conditions.join('; ')}"
      end

      previous_status = 'in_progress'
      new_status = was_executed ? 'resolved' : 'pending_review'

      Types::CustomerSuccess::UpdateTicketResult.new(
        ticket_updated: true,
        ticket_id: ticket_id,
        previous_status: previous_status,
        new_status: new_status,
        resolution_note: resolution_note,
        updated_at: Time.current.iso8601,
        refund_completed: was_executed,
        delegated_task_id: delegated_task_id,
        namespace: 'customer_success_rb',
        update_id: "upd_#{SecureRandom.hex(8)}",
        ticket_status: ticket_status,
        resolution_category: resolution_category,
        timeline: timeline,
        internal_notes: notes.join("\n"),
        customer_facing_message: if was_executed
                                   "Your refund of $#{format('%.2f', validation['refund_amount'].to_f)} " \
                                     'has been processed. Please allow 5-7 business days for the credit to appear.'
                                 else
                                   'We were unable to process your refund request at this time. ' \
                                     'A customer success agent will follow up with more details.'
                                 end,
        satisfaction_survey_scheduled: was_executed,
        follow_up_required: !was_executed
      )
    end
  end
end
