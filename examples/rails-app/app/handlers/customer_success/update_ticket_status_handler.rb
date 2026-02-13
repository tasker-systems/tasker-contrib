module CustomerSuccess
  module StepHandlers
    class UpdateTicketStatusHandler < TaskerCore::StepHandler::Base
      def call(context)
        # TAS-137: Use get_dependency_result() for upstream step results (auto-unwraps)
        validation = context.get_dependency_result('validate_refund_request')
        validation = validation&.is_a?(Hash) ? validation : nil
        policy_check = context.get_dependency_result('check_refund_policy')
        policy_check = policy_check&.is_a?(Hash) ? policy_check : nil
        approval = context.get_dependency_result('get_manager_approval')
        approval = approval&.is_a?(Hash) ? approval : nil
        execution = context.get_dependency_result('execute_refund_workflow')
        execution = execution&.is_a?(Hash) ? execution : nil

        # TAS-137: Use get_dependency_field() for nested field extraction
        ticket_id = context.get_dependency_field('validate_refund_request', 'ticket_id')
        customer_id = context.get_dependency_field('validate_refund_request', 'customer_id')
        delegated_task_id = context.get_dependency_field('execute_refund_workflow', 'delegated_task_id')
        correlation_id = context.get_dependency_field('execute_refund_workflow', 'correlation_id')

        # TAS-137: Use get_input() for task context access
        refund_amount_input = context.get_input('refund_amount')
        refund_reason_input = context.get_input('refund_reason')

        raise TaskerCore::Errors::PermanentError.new(
          'Upstream data not available for ticket update',
          error_code: 'MISSING_DEPENDENCIES'
        ) if validation.nil? || execution.nil?

        was_approved = approval&.dig('approved') == true
        was_executed = execution&.dig('executed') == true || execution&.dig('task_delegated') == true

        # Determine final ticket status
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

        # Build timeline of events
        timeline = [
          { event: 'ticket_opened', timestamp: validation['validated_at'] },
          { event: 'request_validated', timestamp: validation['validated_at'] }
        ]

        if policy_check
          timeline << { event: 'policy_checked', result: policy_check['policy_passed'] ? 'passed' : 'failed', timestamp: policy_check['checked_at'] }
        end

        if approval
          timeline << { event: 'approval_decision', result: approval['approved'] ? 'approved' : 'denied', timestamp: approval['decided_at'] }
        end

        if execution
          timeline << { event: 'refund_execution', result: was_executed ? 'completed' : 'skipped', timestamp: execution['executed_at'] || execution['delegation_timestamp'] }
        end

        timeline << { event: 'ticket_closed', result: ticket_status, timestamp: Time.current.iso8601 }

        # Build resolution note
        resolution_note = "Refund of $#{'%.2f' % validation['refund_amount'].to_f} for order #{validation['order_ref']}. " \
                         "Reason: #{validation['reason']}. " \
                         "Delegated task ID: #{delegated_task_id}. " \
                         "Correlation ID: #{correlation_id}"

        # Build internal notes
        notes = []
        notes << "Refund of $#{'%.2f' % validation['refund_amount'].to_f} for order #{validation['order_ref']}"
        notes << "Reason: #{validation['reason']}"
        notes << "Policy: #{policy_check&.dig('policy_passed') ? 'Passed' : 'Failed'}"
        notes << "Approval: #{approval&.dig('approval_level') || 'N/A'} - #{approval&.dig('approved') ? 'Approved' : 'Denied'}"
        notes << "Execution: #{was_executed ? 'Completed' : 'Not executed'}"

        if (conditions = approval&.dig('conditions')) && conditions.any?
          notes << "Conditions: #{conditions.join('; ')}"
        end

        previous_status = 'in_progress'
        new_status = was_executed ? 'resolved' : 'pending_review'

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            ticket_updated: true,
            ticket_id: ticket_id,
            previous_status: previous_status,
            new_status: new_status,
            resolution_note: resolution_note,
            updated_at: Time.current.iso8601,
            refund_completed: was_executed,
            delegated_task_id: delegated_task_id,
            namespace: 'customer_success',
            update_id: "upd_#{SecureRandom.hex(8)}",
            ticket_status: ticket_status,
            resolution_category: resolution_category,
            timeline: timeline,
            internal_notes: notes.join("\n"),
            customer_facing_message: was_executed ?
              "Your refund of $#{'%.2f' % validation['refund_amount'].to_f} has been processed. Please allow 5-7 business days for the credit to appear." :
              "We were unable to process your refund request at this time. A customer success agent will follow up with more details.",
            satisfaction_survey_scheduled: was_executed,
            follow_up_required: !was_executed
          },
          metadata: {
            handler: self.class.name,
            ticket_id: ticket_id,
            new_status: new_status,
            ticket_status: ticket_status,
            resolution_category: resolution_category,
            was_refunded: was_executed,
            refund_completed: was_executed
          }
        )
      end
    end
  end
end
