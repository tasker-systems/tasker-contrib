module DataPipeline
  module StepHandlers
    class AggregateMetricsHandler < TaskerCore::StepHandler::Base
      def call(context)
        sales_transform = context.get_dependency_field('transform_sales', ['result'])
        inventory_transform = context.get_dependency_field('transform_inventory', ['result'])
        customer_transform = context.get_dependency_field('transform_customers', ['result'])

        raise TaskerCore::Errors::PermanentError.new(
          'One or more transform results are missing',
          error_code: 'MISSING_TRANSFORMS'
        ) if sales_transform.nil? || inventory_transform.nil? || customer_transform.nil?

        total_revenue = sales_transform['total_revenue'].to_f
        total_inventory_value = inventory_transform['total_inventory_value'].to_f
        total_customers = customer_transform['source_record_count'].to_i

        # Cross-source metrics
        revenue_per_customer = total_customers > 0 ? (total_revenue / total_customers).round(2) : 0.0
        inventory_to_revenue_ratio = total_revenue > 0 ? (total_inventory_value / total_revenue).round(3) : 0.0

        # Sales velocity
        top_product = sales_transform['top_product']
        top_region = sales_transform['top_region']

        # Inventory health
        overall_reorder_rate = inventory_transform['overall_reorder_rate'].to_f
        stockout_risk = inventory_transform['stockout_risk_count'].to_i
        avg_lead_time = inventory_transform['average_supplier_lead_days'].to_f

        # Customer health
        churn_risk_rate = customer_transform['churn_risk_rate'].to_f
        engagement_rate = customer_transform['overall_engagement_rate'].to_f

        # Composite scores (0-100)
        sales_health = [100, [(total_revenue / 10_000.0 * 100).round(0), 0].max].min
        inventory_health = [100, (100 - overall_reorder_rate - stockout_risk).round(0)].max
        customer_health = [100, (engagement_rate * (1 - churn_risk_rate / 100)).round(0)].max
        overall_health = ((sales_health + inventory_health + customer_health) / 3.0).round(0)

        # Category cross-reference
        sales_by_channel = (sales_transform['channel_metrics'] || []).map do |cm|
          { channel: cm['channel'], revenue: cm['total_revenue'], share: cm['revenue_share'] }
        end

        customer_by_segment = (customer_transform['segment_metrics'] || []).map do |sm|
          { segment: sm['segment'], count: sm['customer_count'], avg_ltv: sm['average_lifetime_value'] }
        end

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            aggregation_id: "agg_#{SecureRandom.hex(8)}",
            summary: {
              total_revenue: total_revenue,
              total_inventory_value: total_inventory_value,
              total_customers: total_customers,
              revenue_per_customer: revenue_per_customer,
              inventory_to_revenue_ratio: inventory_to_revenue_ratio
            },
            health_scores: {
              sales: sales_health,
              inventory: inventory_health,
              customer: customer_health,
              overall: overall_health
            },
            highlights: {
              top_product: top_product,
              top_region: top_region,
              churn_risk_rate: churn_risk_rate,
              engagement_rate: engagement_rate,
              reorder_rate: overall_reorder_rate,
              stockout_risk_items: stockout_risk,
              avg_supplier_lead_days: avg_lead_time
            },
            breakdowns: {
              sales_by_channel: sales_by_channel,
              customer_by_segment: customer_by_segment
            },
            data_sources: {
              sales_records: sales_transform['source_record_count'],
              inventory_records: inventory_transform['source_record_count'],
              customer_records: customer_transform['source_record_count']
            },
            aggregated_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            overall_health_score: overall_health,
            data_sources_count: 3,
            total_records_processed: [
              sales_transform['source_record_count'].to_i,
              inventory_transform['source_record_count'].to_i,
              customer_transform['source_record_count'].to_i
            ].sum
          }
        )
      end
    end
  end
end
