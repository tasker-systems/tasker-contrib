module Ecommerce
  module StepHandlers
    class ValidateCartHandler < TaskerCore::StepHandler::Base
      TAX_RATE = 0.08
      SHIPPING_THRESHOLD = 75.00
      SHIPPING_COST = 9.99
      MAX_QUANTITY_PER_ITEM = 100
      KNOWN_SKUS = %w[SKU-001 SKU-002 SKU-003 SKU-004 SKU-005].freeze

      def call(context)
        cart_items = context.get_input('cart_items')
        customer_email = context.get_input('customer_email')

        raise TaskerCore::Errors::PermanentError.new(
          'Cart is empty',
          error_code: 'EMPTY_CART'
        ) if cart_items.nil? || cart_items.empty?

        raise TaskerCore::Errors::PermanentError.new(
          'Customer email is required',
          error_code: 'MISSING_EMAIL'
        ) if customer_email.blank?

        validated_items = []
        subtotal = 0.0

        cart_items.each do |item|
          sku      = item['sku']
          name     = item['name']
          quantity = item['quantity'].to_i
          price    = item['unit_price'].to_f

          raise TaskerCore::Errors::PermanentError.new(
            "Invalid quantity for #{sku}: #{quantity}",
            error_code: 'INVALID_QUANTITY'
          ) if quantity < 1 || quantity > MAX_QUANTITY_PER_ITEM

          raise TaskerCore::Errors::PermanentError.new(
            "Invalid price for #{sku}: #{price}",
            error_code: 'INVALID_PRICE'
          ) if price <= 0

          line_total = (quantity * price).round(2)
          subtotal += line_total

          validated_items << {
            sku: sku,
            name: name,
            quantity: quantity,
            unit_price: price,
            line_total: line_total,
            available: true,
            validated_at: Time.current.iso8601
          }
        end

        tax = (subtotal * TAX_RATE).round(2)
        shipping = subtotal >= SHIPPING_THRESHOLD ? 0.0 : SHIPPING_COST
        total = (subtotal + tax + shipping).round(2)

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            validated_items: validated_items,
            item_count: validated_items.size,
            subtotal: subtotal,
            tax: tax,
            tax_rate: TAX_RATE,
            shipping: shipping,
            total: total,
            free_shipping: shipping == 0.0,
            validation_id: SecureRandom.uuid,
            validated_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            items_validated: validated_items.size,
            subtotal: subtotal,
            total: total
          }
        )
      end
    end
  end
end
