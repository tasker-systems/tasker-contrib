module DataPipeline
  module StepHandlers
    class TransformCustomersHandler < TaskerCore::StepHandler::Base
      def call(context)
        # TAS-137: Use get_dependency_result() for upstream step results (auto-unwraps)
        extraction = context.get_dependency_result('extract_customer_data')

        raise TaskerCore::Errors::PermanentError.new(
          'Customer extraction data not available',
          error_code: 'MISSING_EXTRACTION'
        ) if extraction.nil?

        records = extraction['records'] || []

        raise TaskerCore::Errors::PermanentError.new(
          'No customer records to transform',
          error_code: 'EMPTY_DATASET'
        ) if records.empty?

        # Segment analysis
        by_segment = records.group_by { |r| r['segment'] }
        segment_metrics = by_segment.map do |segment, customers|
          avg_ltv = (customers.sum { |c| c['lifetime_value'].to_f } / customers.size).round(2)
          avg_orders = (customers.sum { |c| c['total_orders'].to_i }.to_f / customers.size).round(1)
          engagement = (customers.count { |c| c['email_engaged'] }.to_f / customers.size * 100).round(1)
          {
            segment: segment,
            customer_count: customers.size,
            percentage_of_total: ((customers.size.to_f / records.size) * 100).round(1),
            average_lifetime_value: avg_ltv,
            average_orders: avg_orders,
            email_engagement_rate: engagement,
            average_days_since_order: (customers.sum { |c| c['days_since_last_order'].to_i }.to_f / customers.size).round(0)
          }
        end.sort_by { |m| -m[:average_lifetime_value] }

        # Tier analysis
        by_tier = records.group_by { |r| r['tier'] }
        tier_metrics = by_tier.map do |tier, customers|
          total_ltv = customers.sum { |c| c['lifetime_value'].to_f }
          {
            tier: tier,
            customer_count: customers.size,
            total_lifetime_value: total_ltv.round(2),
            average_lifetime_value: (total_ltv / customers.size).round(2)
          }
        end.sort_by { |m| -m[:total_lifetime_value] }

        # Acquisition channel analysis
        by_channel = records.group_by { |r| r['acquisition_channel'] }
        channel_metrics = by_channel.map do |channel, customers|
          avg_ltv = (customers.sum { |c| c['lifetime_value'].to_f } / customers.size).round(2)
          {
            channel: channel,
            customer_count: customers.size,
            average_lifetime_value: avg_ltv,
            retention_estimate: (rand(0.3..0.85)).round(2)
          }
        end.sort_by { |m| -m[:average_lifetime_value] }

        # Cohort analysis (simplified by region)
        by_region = records.group_by { |r| r['region'] }
        region_metrics = by_region.map do |region, customers|
          {
            region: region,
            customer_count: customers.size,
            average_ltv: (customers.sum { |c| c['lifetime_value'].to_f } / customers.size).round(2)
          }
        end

        # Churn risk assessment
        at_risk = records.select { |r| r['days_since_last_order'].to_i > 90 }
        churn_rate = ((at_risk.size.to_f / records.size) * 100).round(1)

        # Build tier_analysis and value_segments for source compatibility
        tier_analysis = by_tier.transform_values do |tier_records|
          {
            customer_count: tier_records.count,
            total_lifetime_value: tier_records.sum { |r| r['lifetime_value'].to_f },
            avg_lifetime_value: tier_records.sum { |r| r['lifetime_value'].to_f } / tier_records.count.to_f
          }
        end

        total_lifetime_value = records.sum { |r| r['lifetime_value'].to_f }
        avg_customer_value = total_lifetime_value / records.count.to_f

        value_segments = {
          high_value: records.count { |r| r['lifetime_value'].to_f >= 10_000 },
          medium_value: records.count { |r| r['lifetime_value'].to_f.between?(1000, 9999) },
          low_value: records.count { |r| r['lifetime_value'].to_f < 1000 }
        }

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            record_count: records.size,
            tier_analysis: tier_analysis,
            value_segments: value_segments,
            total_lifetime_value: total_lifetime_value.round(2),
            avg_customer_value: avg_customer_value.round(2),
            transformation_type: 'customer_analytics',
            source: 'extract_customer_data',
            transform_id: "tfm_cust_#{SecureRandom.hex(8)}",
            source_record_count: records.size,
            segment_metrics: segment_metrics,
            tier_metrics: tier_metrics,
            channel_metrics: channel_metrics,
            region_metrics: region_metrics,
            churn_risk_rate: churn_rate,
            at_risk_customer_count: at_risk.size,
            overall_engagement_rate: (records.count { |r| r['email_engaged'] }.to_f / records.size * 100).round(1),
            transformed_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            input_records: records.size,
            segments_analyzed: segment_metrics.size,
            churn_risk_rate: churn_rate
          }
        )
      end
    end
  end
end
