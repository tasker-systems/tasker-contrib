module CustomerSuccess
  module StepHandlers
    class UpdateTicketStatusHandler < TaskerCore::StepHandler::Base
      def call(context)
        validation = context.get_dependency_field('validate_refund_request', ['result'])
        policy_check = context.get_dependency_field('check_refund_policy', ['result'])
        approval = context.get_dependency_field('get_manager_approval', ['result'])
        execution = context.get_dependency_field('execute_refund_workflow', ['result'])

        raise TaskerCore::Errors::PermanentError.new(
          'Upstream data not available for ticket update',
          error_code: 'MISSING_DEPENDENCIES'
        ) if validation.nil? || execution.nil?

        ticket_id = validation['ticket_id']
        was_approved = approval&.dig('approved') == true
        was_executed = execution&.dig('executed') == true

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
          timeline << { event: 'refund_execution', result: execution['executed'] ? 'completed' : 'skipped', timestamp: execution['executed_at'] }
        end

        timeline << { event: 'ticket_closed', result: ticket_status, timestamp: Time.current.iso8601 }

        # Build internal note
        notes = []
        notes << "Refund of $#{'%.2f' % validation['refund_amount'].to_f} for order #{validation['order_ref']}"
        notes << "Reason: #{validation['reason']}"
        notes << "Policy: #{policy_check&.dig('policy_passed') ? 'Passed' : 'Failed'}"
        notes << "Approval: #{approval&.dig('approval_level') || 'N/A'} - #{approval&.dig('approved') ? 'Approved' : 'Denied'}"
        notes << "Execution: #{execution&.dig('executed') ? 'Completed' : 'Not executed'}"

        if (conditions = approval&.dig('conditions')) && conditions.any?
          notes << "Conditions: #{conditions.join('; ')}"
        end

        satisfaction_survey_scheduled = was_executed

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            update_id: "upd_#{SecureRandom.hex(8)}",
            ticket_id: ticket_id,
            ticket_status: ticket_status,
            resolution_category: resolution_category,
            timeline: timeline,
            internal_notes: notes.join("\n"),
            customer_facing_message: was_executed ?
              "Your refund of $#{'%.2f' % validation['refund_amount'].to_f} has been processed. Please allow 5-7 business days for the credit to appear." :
              "We were unable to process your refund request at this time. A customer success agent will follow up with more details.",
            satisfaction_survey_scheduled: satisfaction_survey_scheduled,
            follow_up_required: !was_executed,
            updated_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            ticket_id: ticket_id,
            ticket_status: ticket_status,
            resolution_category: resolution_category,
            was_refunded: was_executed
          }
        )
      end
    end
  end
end
