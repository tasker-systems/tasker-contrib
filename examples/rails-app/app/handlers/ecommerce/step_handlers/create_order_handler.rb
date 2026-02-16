module Ecommerce
  module StepHandlers
    class CreateOrderHandler < TaskerCore::StepHandler::Base
      def call(context)
        # Read top-level context fields (matching what the controller sends)
        customer_email = context.get_input('customer_email')
        shipping_address = context.get_input('shipping_address')
        shipping_address = shipping_address&.deep_symbolize_keys

        # TAS-137: Use get_dependency_result() for upstream step results (auto-unwraps)
        cart_validation = context.get_dependency_result('validate_cart')
        cart_validation = cart_validation&.deep_symbolize_keys
        payment_result = context.get_dependency_result('process_payment')
        payment_result = payment_result&.deep_symbolize_keys
        inventory_result = context.get_dependency_result('update_inventory')
        inventory_result = inventory_result&.deep_symbolize_keys

        raise TaskerCore::Errors::PermanentError.new(
          'Missing upstream data for order creation',
          error_code: 'MISSING_DEPENDENCIES'
        ) if cart_validation.nil? || payment_result.nil? || inventory_result.nil?

        order_id = "ORD-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(6).upcase}"
        order_number = SecureRandom.random_number(100_000..999_999)

        validated_items = cart_validation[:validated_items] || []
        items_with_details = validated_items.map do |item|
          item = item.deep_symbolize_keys if item.is_a?(Hash)
          {
            sku: item[:sku],
            name: item[:name],
            quantity: item[:quantity],
            unit_price: item[:unit_price],
            line_total: item[:line_total]
          }
        end

        estimated_shipping_days = case shipping_address&.dig(:country)
                                  when 'US' then rand(3..7)
                                  when 'CA' then rand(5..10)
                                  else rand(7..21)
                                  end

        estimated_delivery = (Time.current + estimated_shipping_days.days).to_date
        total_amount = cart_validation[:total]

        order_record = {
          order_id: order_id,
          order_number: "ORD-#{Date.today.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}",
          status: 'confirmed',
          total_amount: total_amount,
          customer_email: customer_email,
          created_at: Time.current.iso8601,
          estimated_delivery: estimated_delivery.iso8601,
          items: items_with_details,
          subtotal: cart_validation[:subtotal],
          tax: cart_validation[:tax],
          shipping: cart_validation[:shipping],
          payment: {
            payment_id: payment_result[:payment_id],
            transaction_id: payment_result[:transaction_id],
            amount_charged: payment_result[:amount_charged],
            status: payment_result[:status]
          },
          inventory: {
            inventory_log_id: inventory_result[:inventory_log_id]
          },
          shipping_address: shipping_address,
          estimated_shipping_days: estimated_shipping_days
        }

        TaskerCore::Types::StepHandlerCallResult.success(
          result: order_record,
          metadata: {
            handler: self.class.name,
            order_id: order_id,
            item_count: items_with_details.size,
            total_amount: total_amount
          }
        )
      end
    end
  end
end
