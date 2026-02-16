module Ecommerce
  module StepHandlers
    class UpdateInventoryHandler < TaskerCore::StepHandler::Base
      # Simulated warehouse stock levels
      SIMULATED_STOCK = {
        'SKU-001' => 500,
        'SKU-002' => 250,
        'SKU-003' => 100,
        'SKU-004' => 75,
        'SKU-005' => 1000
      }.freeze

      DEFAULT_STOCK = 200

      def call(context)
        # TAS-137: Use get_dependency_result() for upstream step results (auto-unwraps)
        cart_validation = context.get_dependency_result('validate_cart')
        cart_validation = cart_validation&.deep_symbolize_keys

        # TAS-137: Use get_input() for task context access (cross-language standard)
        customer_info = context.get_input('customer_info')
        customer_info = customer_info&.deep_symbolize_keys

        raise TaskerCore::Errors::PermanentError.new(
          'Cart validation data not available',
          error_code: 'MISSING_CART_VALIDATION'
        ) if cart_validation.nil?

        validated_items = cart_validation[:validated_items]

        raise TaskerCore::Errors::PermanentError.new(
          'No validated items found',
          error_code: 'NO_ITEMS'
        ) if validated_items.nil? || validated_items.empty?

        reservation_id = "res_#{SecureRandom.hex(10)}"
        updated_products = []
        inventory_changes = []
        total_reserved = 0
        out_of_stock = []

        validated_items.each do |item|
          item = item.deep_symbolize_keys if item.is_a?(Hash)
          sku = item[:sku] || item[:product_id].to_s
          requested_qty = (item[:quantity] || 0).to_i
          available_stock = SIMULATED_STOCK.fetch(sku, DEFAULT_STOCK)

          if requested_qty > available_stock
            out_of_stock << {
              sku: sku,
              requested: requested_qty,
              available: available_stock
            }
            next
          end

          remaining_after = available_stock - requested_qty
          reservation_entry_id = "rsv_#{SecureRandom.hex(8)}"

          updated_products << {
            product_id: sku,
            name: item[:name] || sku,
            previous_stock: available_stock,
            new_stock: remaining_after,
            quantity_reserved: requested_qty,
            reservation_id: reservation_entry_id
          }

          inventory_changes << {
            product_id: sku,
            change_type: 'reservation',
            quantity: -requested_qty,
            reason: 'order_checkout',
            timestamp: Time.current.iso8601,
            reservation_id: reservation_entry_id,
            inventory_log_id: "log_#{SecureRandom.hex(6)}"
          }

          total_reserved += requested_qty
        end

        unless out_of_stock.empty?
          raise TaskerCore::Errors::PermanentError.new(
            "Insufficient stock for: #{out_of_stock.map { |o| o[:sku] }.join(', ')}",
            error_code: 'OUT_OF_STOCK'
          )
        end

        inventory_log_id = "log_#{SecureRandom.hex(8)}"

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            updated_products: updated_products,
            total_items_reserved: total_reserved,
            inventory_changes: inventory_changes,
            inventory_log_id: inventory_log_id,
            updated_at: Time.current.iso8601,
            reservation_id: reservation_id,
            reservation_expires_at: (Time.current + 30.minutes).iso8601,
            all_items_reserved: true
          },
          metadata: {
            handler: self.class.name,
            reservation_id: reservation_id,
            items_reserved: updated_products.size,
            total_reserved: total_reserved
          }
        )
      end
    end
  end
end
