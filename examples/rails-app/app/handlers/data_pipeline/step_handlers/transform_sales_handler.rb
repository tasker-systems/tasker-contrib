module DataPipeline
  module StepHandlers
    class TransformSalesHandler < TaskerCore::StepHandler::Base
      def call(context)
        # TAS-137: Use get_dependency_result() for upstream step results (auto-unwraps)
        extraction = context.get_dependency_result('extract_sales_data')

        raise TaskerCore::Errors::PermanentError.new(
          'Sales extraction data not available',
          error_code: 'MISSING_EXTRACTION'
        ) if extraction.nil?

        records = extraction['records'] || []

        raise TaskerCore::Errors::PermanentError.new(
          'No sales records to transform',
          error_code: 'EMPTY_DATASET'
        ) if records.empty?

        # Group by product
        by_product = records.group_by { |r| r['product'] }
        product_metrics = by_product.map do |product, sales|
          revenue = sales.sum { |s| s['revenue'].to_f }
          qty = sales.sum { |s| s['quantity'].to_i }
          {
            product: product,
            total_revenue: revenue.round(2),
            total_quantity: qty,
            transaction_count: sales.size,
            average_revenue_per_sale: (revenue / sales.size).round(2),
            average_quantity_per_sale: (qty.to_f / sales.size).round(1)
          }
        end.sort_by { |m| -m[:total_revenue] }

        # Group by region
        by_region = records.group_by { |r| r['region'] }
        region_metrics = by_region.map do |region, sales|
          revenue = sales.sum { |s| s['revenue'].to_f }
          {
            region: region,
            total_revenue: revenue.round(2),
            transaction_count: sales.size,
            average_order_value: (revenue / sales.size).round(2)
          }
        end.sort_by { |m| -m[:total_revenue] }

        # Group by channel
        by_channel = records.group_by { |r| r['channel'] }
        channel_metrics = by_channel.map do |channel, sales|
          revenue = sales.sum { |s| s['revenue'].to_f }
          {
            channel: channel,
            total_revenue: revenue.round(2),
            transaction_count: sales.size,
            revenue_share: 0.0 # filled below
          }
        end
        total_revenue = channel_metrics.sum { |m| m[:total_revenue] }
        channel_metrics.each { |m| m[:revenue_share] = ((m[:total_revenue] / total_revenue) * 100).round(1) }

        # Discount analysis
        discounted = records.select { |r| r['discount_rate'].to_f > 0 }
        avg_discount = discounted.empty? ? 0.0 : (discounted.sum { |r| r['discount_rate'].to_f } / discounted.size).round(3)

        # Build daily_sales and product_sales for source compatibility
        daily_sales = records.group_by { |r| r['sale_date'] }
                             .transform_values do |day_records|
                               {
                                 total_amount: day_records.sum { |r| r['revenue'].to_f },
                                 order_count: day_records.count,
                                 avg_order_value: day_records.sum { |r| r['revenue'].to_f } / day_records.count.to_f
                               }
        end

        product_sales = records.group_by { |r| r['product'] }
                               .transform_values do |product_records|
                                 {
                                   total_quantity: product_records.sum { |r| r['quantity'].to_i },
                                   total_revenue: product_records.sum { |r| r['revenue'].to_f },
                                   order_count: product_records.count
                                 }
        end

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            record_count: records.size,
            daily_sales: daily_sales,
            product_sales: product_sales,
            total_revenue: total_revenue.round(2),
            transformation_type: 'sales_analytics',
            source: 'extract_sales_data',
            transform_id: "tfm_sales_#{SecureRandom.hex(8)}",
            source_record_count: records.size,
            product_metrics: product_metrics,
            region_metrics: region_metrics,
            channel_metrics: channel_metrics,
            average_discount_rate: avg_discount,
            discount_usage_rate: ((discounted.size.to_f / records.size) * 100).round(1),
            top_product: product_metrics.first&.dig(:product),
            top_region: region_metrics.first&.dig(:region),
            transformed_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            input_records: records.size,
            products_analyzed: product_metrics.size,
            regions_analyzed: region_metrics.size,
            total_revenue: total_revenue.round(2)
          }
        )
      end
    end
  end
end
