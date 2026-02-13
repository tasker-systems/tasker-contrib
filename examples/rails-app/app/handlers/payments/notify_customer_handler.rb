module Payments
  module StepHandlers
    class NotifyCustomerHandler < TaskerCore::StepHandler::Base
      def call(context)
        # TAS-137: Use get_dependency_result() for upstream step results (auto-unwraps)
        eligibility = context.get_dependency_result('validate_payment_eligibility')
        eligibility = eligibility&.is_a?(Hash) ? eligibility : nil
        gateway_result = context.get_dependency_result('process_gateway_refund')
        gateway_result = gateway_result&.is_a?(Hash) ? gateway_result : nil
        records_result = context.get_dependency_result('update_payment_records')
        records_result = records_result&.is_a?(Hash) ? records_result : nil

        # TAS-137: Use get_dependency_field() for nested field extraction
        refund_id = context.get_dependency_field('process_gateway_refund', 'refund_id')
        refund_amount_dep = context.get_dependency_field('process_gateway_refund', 'refund_amount')
        payment_id = context.get_dependency_field('process_gateway_refund', 'payment_id')
        estimated_arrival = context.get_dependency_field('process_gateway_refund', 'estimated_arrival')

        # TAS-137: Use get_input() for task context access
        customer_email = context.get_input('customer_email')
        # TAS-137: Use get_input_or() for task context with default
        refund_reason = context.get_input_or('refund_reason', 'customer_request')

        raise TaskerCore::Errors::PermanentError.new(
          'Upstream data not available for customer notification',
          error_code: 'MISSING_DEPENDENCIES'
        ) if eligibility.nil? || gateway_result.nil? || records_result.nil?

        payment_id ||= eligibility['payment_id']
        amount = (refund_amount_dep || gateway_result['refund_amount']).to_f
        currency = gateway_result['currency']
        settlement = gateway_result['settlement'] || {}
        reason = refund_reason || eligibility['reason'] || 'refund_processed'

        notification_id = "notif_#{SecureRandom.hex(10)}"
        sent_at = Time.current

        # Build customer-facing notification content
        formatted_amount = "#{currency} #{'%.2f' % amount}"
        settlement_message = if settlement['estimated_days']
                               "Please allow #{settlement['estimated_days']} business days for the refund to appear on your statement."
                             else
                               'Your refund will be processed within the standard settlement period.'
                             end

        # Send through multiple channels
        notifications = []

        # Email notification
        email_message_id = "email_#{SecureRandom.hex(12)}"
        notifications << {
          channel: 'email',
          message_id: email_message_id,
          subject: "Refund Processed - #{formatted_amount}",
          body_preview: "Your refund of #{formatted_amount} for payment #{payment_id} has been processed. #{settlement_message}",
          template: 'refund_confirmation',
          template_variables: {
            amount: formatted_amount,
            payment_id: payment_id,
            settlement_message: settlement_message,
            reason: reason.humanize,
            support_url: 'https://support.example.com/refunds'
          },
          status: 'sent',
          sent_at: sent_at.iso8601
        }

        # Push notification
        notifications << {
          channel: 'push',
          message_id: "push_#{SecureRandom.hex(8)}",
          title: 'Refund Processed',
          body: "Your refund of #{formatted_amount} has been processed.",
          action: 'view_payment_details',
          action_data: { payment_id: payment_id },
          status: 'delivered',
          sent_at: sent_at.iso8601
        }

        # In-app notification
        notifications << {
          channel: 'in_app',
          message_id: "inapp_#{SecureRandom.hex(8)}",
          title: 'Refund Confirmed',
          body: "#{formatted_amount} refund for payment #{payment_id}. #{settlement_message}",
          category: 'payment',
          priority: 'normal',
          action_url: "/payments/#{payment_id}/refunds",
          expires_at: (sent_at + 30.days).iso8601,
          status: 'created',
          sent_at: sent_at.iso8601
        }

        # Webhook notification (for API integrations)
        notifications << {
          channel: 'webhook',
          message_id: "wh_#{SecureRandom.hex(8)}",
          event_type: 'payment.refunded',
          payload: {
            payment_id: payment_id,
            refund_amount: amount,
            currency: currency,
            gateway_transaction_id: gateway_result['gateway_transaction_id'],
            status: 'processed',
            timestamp: sent_at.iso8601
          },
          status: 'dispatched',
          sent_at: sent_at.iso8601
        }

        all_sent = notifications.all? { |n| %w[sent delivered created dispatched].include?(n[:status]) }

        message_id = email_message_id

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            notification_sent: true,
            customer_email: customer_email || 'customer@example.com',
            message_id: message_id,
            notification_type: 'refund_confirmation',
            sent_at: sent_at.iso8601,
            delivery_status: all_sent ? 'delivered' : 'partial',
            refund_id: refund_id,
            refund_amount: amount,
            namespace: 'payments',
            notification_id: notification_id,
            payment_id: payment_id,
            currency: currency,
            notifications: notifications,
            total_notifications: notifications.size,
            all_sent: all_sent,
            channels_used: notifications.map { |n| n[:channel] },
            settlement_info: {
              estimated_days: settlement['estimated_days'],
              estimated_date: settlement['estimated_date'],
              method: settlement['method']
            },
            notified_at: sent_at.iso8601
          },
          metadata: {
            handler: self.class.name,
            notification_id: notification_id,
            message_id: message_id,
            customer_email: customer_email,
            notification_type: 'refund_confirmation',
            channels_used: notifications.map { |n| n[:channel] },
            all_sent: all_sent,
            amount: formatted_amount
          }
        )
      end
    end
  end
end
