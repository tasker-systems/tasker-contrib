module Ecommerce
  module StepHandlers
    class SendConfirmationHandler < TaskerCore::StepHandler::Base
      def call(context)
        # TAS-137: Use get_input() for task context access (cross-language standard)
        customer_info = context.get_input('customer_info')
        customer_info = customer_info&.deep_symbolize_keys || {}
        customer_email = customer_info[:email]

        # TAS-137: Use get_dependency_result() for upstream step results (auto-unwraps)
        order_result = context.get_dependency_result('create_order')
        order_result = order_result&.deep_symbolize_keys

        cart_validation = context.get_dependency_result('validate_cart')
        cart_validation = cart_validation&.deep_symbolize_keys

        raise TaskerCore::Errors::PermanentError.new(
          'Order data not available for confirmation',
          error_code: 'MISSING_ORDER_DATA'
        ) if order_result.nil?

        raise TaskerCore::Errors::PermanentError.new(
          'Customer email is required for confirmation',
          error_code: 'MISSING_EMAIL'
        ) if customer_email.blank?

        order_id = order_result[:order_id]
        total = order_result[:total_amount]
        estimated_delivery = order_result[:estimated_delivery]
        item_count = (cart_validation&.dig(:validated_items) || []).size

        message_id = "msg_#{SecureRandom.hex(12)}"
        sent_at = Time.current

        # Build confirmation email content
        email_subject = "Order Confirmed: #{order_id}"
        email_body_summary = [
          "Thank you for your order!",
          "Order: #{order_id}",
          "Items: #{item_count}",
          "Total: $#{'%.2f' % total.to_f}",
          "Estimated delivery: #{estimated_delivery}",
          "A tracking number will be sent when your order ships."
        ].join("\n")

        # Simulate sending through multiple channels
        channels = [
          {
            channel: 'email',
            recipient: customer_email,
            subject: email_subject,
            status: 'delivered',
            message_id: message_id,
            sent_at: sent_at.iso8601
          },
          {
            channel: 'in_app',
            notification_id: "notif_#{SecureRandom.hex(8)}",
            status: 'delivered',
            sent_at: sent_at.iso8601
          }
        ]

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            email_sent: true,
            recipient: customer_email,
            email_type: 'order_confirmation',
            sent_at: sent_at.iso8601,
            message_id: message_id,
            order_id: order_id,
            notifications_sent: channels,
            email_subject: email_subject,
            email_body_preview: email_body_summary.truncate(200),
            total_channels: channels.size,
            all_delivered: channels.all? { |c| c[:status] == 'delivered' },
            confirmation_sent_at: sent_at.iso8601
          },
          metadata: {
            handler: self.class.name,
            order_id: order_id,
            channels_used: channels.map { |c| c[:channel] },
            all_delivered: true
          }
        )
      end
    end
  end
end
