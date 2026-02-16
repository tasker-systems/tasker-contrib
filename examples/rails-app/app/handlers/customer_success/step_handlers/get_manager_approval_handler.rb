module CustomerSuccess
  module StepHandlers
    class GetManagerApprovalHandler < TaskerCore::StepHandler::Base
      def call(context)
        # TAS-137: Use get_dependency_result() for upstream step results (auto-unwraps)
        policy_result_full = context.get_dependency_result('check_refund_policy')
        policy_check = policy_result_full&.is_a?(Hash) ? policy_result_full : nil

        validation_full = context.get_dependency_result('validate_refund_request')
        validation = validation_full&.is_a?(Hash) ? validation_full : nil

        # TAS-137: Use get_dependency_field() for nested field extraction
        requires_approval = context.get_dependency_field('check_refund_policy', 'requires_approval')
        customer_tier_field = context.get_dependency_field('check_refund_policy', 'customer_tier')
        ticket_id = context.get_dependency_field('validate_refund_request', 'ticket_id')
        customer_id_field = context.get_dependency_field('validate_refund_request', 'customer_id')

        # TAS-137: Use get_input() for task context access
        refund_amount_input = context.get_input('refund_amount')
        refund_reason_input = context.get_input('refund_reason')
        agent_id = context.get_input('agent_id')
        priority = context.get_input('priority') || 'normal'

        raise TaskerCore::Errors::PermanentError.new(
          'Upstream data not available for approval routing',
          error_code: 'MISSING_DEPENDENCIES'
        ) if validation.nil? || policy_check.nil?

        # If policy check failed, deny immediately
        unless policy_check['policy_passed']
          return TaskerCore::Types::StepHandlerCallResult.success(
            result: {
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
              violations: policy_check['violations'],
              decision_type: 'automatic',
              decided_by: 'system',
              decided_at: Time.current.iso8601
            },
            metadata: {
              handler: self.class.name,
              approved: false,
              decision_type: 'automatic'
            }
          )
        end

        # If auto-approved, no manager needed
        if policy_check['auto_approve']
          return TaskerCore::Types::StepHandlerCallResult.success(
            result: {
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
            },
            metadata: {
              handler: self.class.name,
              approved: true,
              decision_type: 'automatic'
            }
          )
        end

        # Simulate manager review
        approval_level = policy_check['approval_level']
        amount = validation['refund_amount'].to_f
        approval_id = "apr_#{SecureRandom.hex(8)}"

        # Simulate manager assignment based on level
        manager = case approval_level
                  when 'senior_manager'
                    { id: "mgr_#{SecureRandom.hex(6)}", name: 'Senior Operations Manager', level: 'senior' }
                  else
                    { id: "mgr_#{SecureRandom.hex(6)}", name: 'Team Lead', level: 'standard' }
                  end

        # Simulate approval decision (weighted toward approval for simulation)
        approved = rand < 0.85
        conditions = []

        if approved && amount > 500
          conditions << 'Customer must return defective items within 14 days'
        end

        if approved && validation.dig('order_data', 'previous_refunds').to_i > 1
          conditions << 'Flag customer account for monitoring'
        end

        review_duration_minutes = rand(5..120)

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
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
            requesting_agent: agent_id || 'unassigned',
            priority: priority,
            conditions: conditions,
            review_duration_minutes: review_duration_minutes,
            warnings: policy_check['warnings'] || [],
            decided_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            approval_id: approval_id,
            approved: approved,
            approval_level: approval_level,
            decision_type: 'manual',
            review_minutes: review_duration_minutes
          }
        )
      end
    end
  end
end
