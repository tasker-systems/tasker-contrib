module CustomerSuccess
  module StepHandlers
    class ExecuteRefundWorkflowHandler < TaskerCore::StepHandler::Base
      def call(context)
        # TAS-137: Use get_dependency_result() for upstream step results (auto-unwraps)
        approval_result = context.get_dependency_result('get_manager_approval')
        approval = approval_result&.is_a?(Hash) ? approval_result : nil

        validation_full = context.get_dependency_result('validate_refund_request')
        validation = validation_full&.is_a?(Hash) ? validation_full : nil

        # TAS-137: Use get_dependency_field() for nested field extraction
        payment_id = context.get_dependency_field('validate_refund_request', 'payment_id')
        approval_id = context.get_dependency_field('get_manager_approval', 'approval_id')

        # TAS-137: Use get_input() for task context access
        refund_amount_input = context.get_input('refund_amount')
        refund_reason_input = context.get_input_or('refund_reason', 'customer_request')
        customer_email_input = context.get_input_or('customer_email', 'customer@example.com')
        ticket_id_input = context.get_input('ticket_id')
        correlation_id_input = context.get_input('correlation_id') || "cs-#{SecureRandom.hex(8)}"

        raise TaskerCore::Errors::PermanentError.new(
          'Upstream data not available for refund execution',
          error_code: 'MISSING_DEPENDENCIES'
        ) if validation.nil? || approval.nil?

        # Cannot proceed without approval
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

        # Cross-namespace workflow coordination: delegate to payments namespace
        delegated_task_id = "task_#{SecureRandom.uuid}"
        correlation_id = correlation_id_input

        execution_id = "exec_#{SecureRandom.hex(8)}"
        refund_transaction_id = "rfnd_#{SecureRandom.hex(12)}"

        # Simulate refund processing steps
        steps_executed = []

        # Step 1: Initiate refund with payment processor
        steps_executed << {
          step: 'initiate_refund',
          status: 'completed',
          transaction_id: refund_transaction_id,
          amount: amount,
          payment_method: payment_method,
          completed_at: Time.current.iso8601
        }

        # Step 2: Update order status
        steps_executed << {
          step: 'update_order',
          status: 'completed',
          order_ref: order_ref,
          new_status: 'refunded',
          completed_at: Time.current.iso8601
        }

        # Step 3: Process inventory return if physical goods
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

        # Step 4: Credit customer account
        steps_executed << {
          step: 'credit_account',
          status: 'completed',
          customer_id: customer_id,
          credit_amount: amount,
          estimated_arrival: (Time.current + 5.business_days rescue Time.current + 7.days).iso8601,
          completed_at: Time.current.iso8601
        }

        # Step 5: Update loyalty points (deduct if applicable)
        points_deducted = (amount * 10).round(0)
        steps_executed << {
          step: 'adjust_loyalty_points',
          status: 'completed',
          points_deducted: points_deducted,
          completed_at: Time.current.iso8601
        }

        all_completed = steps_executed.all? { |s| s[:status] == 'completed' }

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
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
          },
          metadata: {
            handler: self.class.name,
            execution_id: execution_id,
            refund_transaction_id: refund_transaction_id,
            amount: amount,
            steps_completed: steps_executed.count { |s| s[:status] == 'completed' },
            target_namespace: 'payments_rb',
            target_workflow: 'process_refund',
            delegated_task_id: delegated_task_id,
            correlation_id: correlation_id
          }
        )
      end
    end
  end
end
