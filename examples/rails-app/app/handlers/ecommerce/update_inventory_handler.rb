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
        cart_validation = context.get_dependency_field('validate_cart', ['result'])

        raise TaskerCore::Errors::PermanentError.new(
          'Cart validation data not available',
          error_code: 'MISSING_CART_VALIDATION'
        ) if cart_validation.nil?

        validated_items = cart_validation['validated_items']

        raise TaskerCore::Errors::PermanentError.new(
          'No validated items found',
          error_code: 'NO_ITEMS'
        ) if validated_items.nil? || validated_items.empty?

        reservation_id = "res_#{SecureRandom.hex(10)}"
        reservations = []
        total_reserved = 0
        out_of_stock = []

        validated_items.each do |item|
          sku = item['sku']
          requested_qty = item['quantity'].to_i
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
          reservations << {
            sku: sku,
            quantity_reserved: requested_qty,
            warehouse_location: "WH-#{Digest::MD5.hexdigest(sku)[0..3].upcase}",
            previous_stock: available_stock,
            remaining_stock: remaining_after,
            low_stock_alert: remaining_after < 20,
            reserved_at: Time.current.iso8601
          }
          total_reserved += requested_qty
        end

        unless out_of_stock.empty?
          raise TaskerCore::Errors::PermanentError.new(
            "Insufficient stock for: #{out_of_stock.map { |o| o[:sku] }.join(', ')}",
            error_code: 'OUT_OF_STOCK'
          )
        end

        low_stock_skus = reservations.select { |r| r[:low_stock_alert] }.map { |r| r[:sku] }

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            reservation_id: reservation_id,
            reservations: reservations,
            total_items_reserved: total_reserved,
            reservation_expires_at: (Time.current + 30.minutes).iso8601,
            low_stock_warnings: low_stock_skus,
            all_items_reserved: true
          },
          metadata: {
            handler: self.class.name,
            reservation_id: reservation_id,
            items_reserved: reservations.size,
            low_stock_count: low_stock_skus.size
          }
        )
      end
    end
  end
end
