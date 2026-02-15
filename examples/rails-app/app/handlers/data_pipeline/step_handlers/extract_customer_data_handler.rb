module DataPipeline
  module StepHandlers
    class ExtractCustomerDataHandler < TaskerCore::StepHandler::Base
      SEGMENTS = %w[new_customer returning loyal churned at_risk].freeze
      TIERS = %w[bronze silver gold platinum].freeze
      ACQUISITION_CHANNELS = %w[organic paid_search social referral direct email].freeze

      def call(context)
        source = context.get_input('source')
        date_range = context.get_input('date_range')

        raise TaskerCore::Errors::PermanentError.new(
          'Source system is required',
          error_code: 'MISSING_SOURCE'
        ) if source.blank?

        start_date = date_range&.dig('start_date') || (Date.current - 30).iso8601

        # Generate customer profile records
        record_count = rand(100..300)
        records = record_count.times.map do |i|
          customer_id = "CUST-#{SecureRandom.hex(6).upcase}"
          segment = SEGMENTS.sample
          lifetime_value = (rand(25.0..5000.0)).round(2)
          order_count = rand(1..50)
          last_order_days_ago = rand(1..365)

          {
            customer_id: customer_id,
            segment: segment,
            tier: TIERS.sample,
            acquisition_channel: ACQUISITION_CHANNELS.sample,
            lifetime_value: lifetime_value,
            total_orders: order_count,
            average_order_value: (lifetime_value / order_count).round(2),
            last_order_date: (Date.current - last_order_days_ago).iso8601,
            days_since_last_order: last_order_days_ago,
            email_engaged: rand < 0.6,
            signup_date: (Date.current - rand(30..730)).iso8601,
            region: %w[US-EAST US-WEST EU-WEST EU-EAST APAC].sample
          }
        end

        avg_ltv = (records.sum { |r| r[:lifetime_value] } / records.size).round(2)
        total_ltv = records.sum { |r| r[:lifetime_value] }
        segment_distribution = records.group_by { |r| r[:segment] }
                                       .transform_values(&:count)
        tier_breakdown = records.group_by { |r| r[:tier] }.transform_values(&:count)

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            source: source,
            extraction_id: "ext_cust_#{SecureRandom.hex(8)}",
            record_count: records.size,
            records: records,
            total_customers: records.size,
            total_lifetime_value: total_ltv.round(2),
            tier_breakdown: tier_breakdown,
            avg_lifetime_value: avg_ltv,
            average_lifetime_value: avg_ltv,
            segment_distribution: segment_distribution,
            engagement_rate: (records.count { |r| r[:email_engaged] }.to_f / records.size).round(3),
            extracted_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            source: source,
            record_count: records.size,
            average_ltv: avg_ltv
          }
        )
      end
    end
  end
end
