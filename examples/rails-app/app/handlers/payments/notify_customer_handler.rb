module Payments
  module StepHandlers
    class NotifyCustomerHandler < TaskerCore::StepHandler::Base
      def call(context)
        eligibility = context.get_dependency_field('validate_payment_eligibility', ['result'])
        gateway_result = context.get_dependency_field('process_gateway_refund', ['result'])
        records_result = context.get_dependency_field('update_payment_records', ['result'])

        raise TaskerCore::Errors::PermanentError.new(
          'Upstream data not available for customer notification',
          error_code: 'MISSING_DEPENDENCIES'
        ) if eligibility.nil? || gateway_result.nil? || records_result.nil?

        payment_id = eligibility['payment_id']
        amount = gateway_result['refund_amount'].to_f
        currency = gateway_result['currency']
        settlement = gateway_result['settlement'] || {}
        reason = eligibility['reason'] || 'refund_processed'

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

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            notification_id: notification_id,
            payment_id: payment_id,
            refund_amount: amount,
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
            channels_used: notifications.map { |n| n[:channel] },
            all_sent: all_sent,
            amount: formatted_amount
          }
        )
      end
    end
  end
end
