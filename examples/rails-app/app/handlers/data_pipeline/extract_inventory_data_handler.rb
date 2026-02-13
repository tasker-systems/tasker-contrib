module DataPipeline
  module StepHandlers
    class ExtractInventoryDataHandler < TaskerCore::StepHandler::Base
      WAREHOUSES = %w[WH-EAST WH-WEST WH-CENTRAL WH-SOUTH].freeze
      CATEGORIES = %w[electronics clothing home_garden sports food_beverage].freeze

      def call(context)
        source = context.get_input('source')
        filters = context.get_input('filters') || {}

        raise TaskerCore::Errors::PermanentError.new(
          'Source system is required',
          error_code: 'MISSING_SOURCE'
        ) if source.blank?

        category_filter = filters['product_category']

        # Generate inventory snapshot records
        record_count = rand(80..200)
        records = record_count.times.map do |i|
          category = CATEGORIES.sample
          next if category_filter.present? && category != category_filter

          sku = "SKU-#{category[0..2].upcase}-#{SecureRandom.hex(3).upcase}"
          on_hand = rand(0..1000)
          reorder_point = rand(10..100)
          unit_cost = (rand(2.50..150.00)).round(2)

          {
            sku: sku,
            category: category,
            warehouse: WAREHOUSES.sample,
            on_hand_quantity: on_hand,
            reserved_quantity: rand(0..[on_hand, 50].min),
            reorder_point: reorder_point,
            needs_reorder: on_hand <= reorder_point,
            unit_cost: unit_cost,
            total_value: (on_hand * unit_cost).round(2),
            last_received_date: (Date.current - rand(1..60)).iso8601,
            supplier_lead_days: rand(3..30)
          }
        end.compact

        total_value = records.sum { |r| r[:total_value] }
        items_needing_reorder = records.count { |r| r[:needs_reorder] }

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            source: source,
            extraction_id: "ext_inv_#{SecureRandom.hex(8)}",
            record_count: records.size,
            records: records,
            total_inventory_value: total_value.round(2),
            items_needing_reorder: items_needing_reorder,
            warehouses_covered: records.map { |r| r[:warehouse] }.uniq,
            extracted_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            source: source,
            record_count: records.size,
            total_value: total_value.round(2),
            reorder_alerts: items_needing_reorder
          }
        )
      end
    end
  end
end
