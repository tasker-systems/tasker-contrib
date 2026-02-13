module DataPipeline
  module StepHandlers
    class TransformInventoryHandler < TaskerCore::StepHandler::Base
      def call(context)
        extraction = context.get_dependency_field('extract_inventory_data', ['result'])

        raise TaskerCore::Errors::PermanentError.new(
          'Inventory extraction data not available',
          error_code: 'MISSING_EXTRACTION'
        ) if extraction.nil?

        records = extraction['records'] || []

        raise TaskerCore::Errors::PermanentError.new(
          'No inventory records to transform',
          error_code: 'EMPTY_DATASET'
        ) if records.empty?

        # Group by category
        by_category = records.group_by { |r| r['category'] }
        category_metrics = by_category.map do |category, items|
          total_value = items.sum { |i| i['total_value'].to_f }
          total_on_hand = items.sum { |i| i['on_hand_quantity'].to_i }
          needing_reorder = items.count { |i| i['needs_reorder'] }
          {
            category: category,
            sku_count: items.size,
            total_on_hand: total_on_hand,
            total_value: total_value.round(2),
            average_unit_cost: (total_value / [total_on_hand, 1].max).round(2),
            items_needing_reorder: needing_reorder,
            reorder_rate: ((needing_reorder.to_f / items.size) * 100).round(1)
          }
        end.sort_by { |m| -m[:total_value] }

        # Group by warehouse
        by_warehouse = records.group_by { |r| r['warehouse'] }
        warehouse_metrics = by_warehouse.map do |warehouse, items|
          total_value = items.sum { |i| i['total_value'].to_f }
          {
            warehouse: warehouse,
            sku_count: items.size,
            total_on_hand: items.sum { |i| i['on_hand_quantity'].to_i },
            total_value: total_value.round(2),
            utilization_score: (rand(0.5..0.95)).round(2)
          }
        end

        # Overall metrics
        total_inventory_value = records.sum { |r| r['total_value'].to_f }
        total_skus = records.size
        avg_lead_time = (records.sum { |r| r['supplier_lead_days'].to_i }.to_f / total_skus).round(1)
        stockout_risk = records.count { |r| r['on_hand_quantity'].to_i == 0 }

        # Turnover estimation (simplified)
        turnover_rates = category_metrics.map do |cm|
          { category: cm[:category], estimated_turnover: (rand(2.0..12.0)).round(1) }
        end

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            transform_id: "tfm_inv_#{SecureRandom.hex(8)}",
            source_record_count: records.size,
            category_metrics: category_metrics,
            warehouse_metrics: warehouse_metrics,
            turnover_rates: turnover_rates,
            total_inventory_value: total_inventory_value.round(2),
            total_skus: total_skus,
            average_supplier_lead_days: avg_lead_time,
            stockout_risk_count: stockout_risk,
            overall_reorder_rate: ((records.count { |r| r['needs_reorder'] }.to_f / total_skus) * 100).round(1),
            transformed_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            input_records: records.size,
            categories_analyzed: category_metrics.size,
            warehouses_analyzed: warehouse_metrics.size,
            total_inventory_value: total_inventory_value.round(2)
          }
        )
      end
    end
  end
end
