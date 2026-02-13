module Ecommerce
  module StepHandlers
    class CreateOrderHandler < TaskerCore::StepHandler::Base
      def call(context)
        customer_email = context.get_input('customer_email')
        shipping_address = context.get_input('shipping_address')
        cart_validation = context.get_dependency_field('validate_cart', ['result'])
        payment_result = context.get_dependency_field('process_payment', ['result'])
        inventory_result = context.get_dependency_field('update_inventory', ['result'])

        raise TaskerCore::Errors::PermanentError.new(
          'Missing upstream data for order creation',
          error_code: 'MISSING_DEPENDENCIES'
        ) if cart_validation.nil? || payment_result.nil? || inventory_result.nil?

        order_id = "ORD-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(6).upcase}"
        order_number = SecureRandom.random_number(100_000..999_999)

        items_with_details = (cart_validation['validated_items'] || []).map do |item|
          reservation = (inventory_result['reservations'] || []).find { |r| r['sku'] == item['sku'] }
          {
            sku: item['sku'],
            name: item['name'],
            quantity: item['quantity'],
            unit_price: item['unit_price'],
            line_total: item['line_total'],
            warehouse_location: reservation&.dig('warehouse_location') || 'UNKNOWN'
          }
        end

        estimated_shipping_days = case shipping_address&.dig('country')
                                  when 'US' then rand(3..7)
                                  when 'CA' then rand(5..10)
                                  else rand(7..21)
                                  end

        estimated_delivery = (Time.current + estimated_shipping_days.days).to_date

        order_record = {
          order_id: order_id,
          order_number: order_number,
          customer_email: customer_email,
          items: items_with_details,
          subtotal: cart_validation['subtotal'],
          tax: cart_validation['tax'],
          shipping: cart_validation['shipping'],
          total: cart_validation['total'],
          payment: {
            transaction_id: payment_result['transaction_id'],
            authorization_code: payment_result['authorization_code'],
            amount_charged: payment_result['amount_charged'],
            status: payment_result['status']
          },
          inventory: {
            reservation_id: inventory_result['reservation_id'],
            expires_at: inventory_result['reservation_expires_at']
          },
          shipping_address: shipping_address,
          estimated_delivery: estimated_delivery.iso8601,
          estimated_shipping_days: estimated_shipping_days,
          status: 'confirmed',
          created_at: Time.current.iso8601
        }

        TaskerCore::Types::StepHandlerCallResult.success(
          result: order_record,
          metadata: {
            handler: self.class.name,
            order_id: order_id,
            item_count: items_with_details.size,
            total: cart_validation['total']
          }
        )
      end
    end
  end
end
