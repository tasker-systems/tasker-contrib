module DataPipeline
  module StepHandlers
    class ExtractSalesDataHandler < TaskerCore::StepHandler::Base
      SAMPLE_PRODUCTS = %w[Widget-A Gadget-B Doohickey-C Thingamajig-D].freeze
      REGIONS = %w[northeast southeast midwest west international].freeze

      def call(context)
        source = context.get_input('source')
        date_range = context.get_input('date_range')
        filters = context.get_input('filters') || {}

        raise TaskerCore::Errors::PermanentError.new(
          'Source system is required',
          error_code: 'MISSING_SOURCE'
        ) if source.blank?

        raise TaskerCore::Errors::RetryableError.new(
          "Source system '#{source}' is temporarily unavailable"
        ) if source == 'staging' && rand < 0.1 # 10% simulated failure for staging

        start_date = date_range&.dig('start_date') || (Date.current - 30).iso8601
        end_date = date_range&.dig('end_date') || Date.current.iso8601
        region_filter = filters['region']

        # Generate realistic sample sales records
        record_count = rand(150..500)
        records = record_count.times.map do |i|
          region = REGIONS.sample
          next if region_filter.present? && region != region_filter

          product = SAMPLE_PRODUCTS.sample
          quantity = rand(1..50)
          unit_price = (rand(9.99..299.99)).round(2)
          discount = rand < 0.3 ? (rand(0.05..0.25)).round(2) : 0.0
          revenue = (quantity * unit_price * (1 - discount)).round(2)

          {
            sale_id: "SALE-#{SecureRandom.hex(6).upcase}",
            product: product,
            region: region,
            quantity: quantity,
            unit_price: unit_price,
            discount_rate: discount,
            revenue: revenue,
            sale_date: (Date.parse(start_date) + rand(0..30)).iso8601,
            channel: %w[online retail wholesale].sample
          }
        end.compact

        total_revenue = records.sum { |r| r[:revenue] }

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            source: source,
            extraction_id: "ext_sales_#{SecureRandom.hex(8)}",
            date_range: { start_date: start_date, end_date: end_date },
            record_count: records.size,
            records: records,
            total_amount: total_revenue.round(2),
            total_revenue: total_revenue.round(2),
            extracted_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            source: source,
            record_count: records.size,
            total_revenue: total_revenue.round(2)
          }
        )
      end
    end
  end
end
