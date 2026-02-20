# frozen_string_literal: true

# Service functions return Dry::Struct instances from Types::DataPipeline.
# See Types::DataPipeline in app/services/types.rb for full struct definitions.
#   extract_sales_data     -> Types::DataPipeline::ExtractSalesResult
#   extract_inventory_data -> Types::DataPipeline::ExtractInventoryResult
#   extract_customer_data  -> Types::DataPipeline::ExtractCustomerResult
#   transform_sales        -> Types::DataPipeline::TransformSalesResult
#   transform_inventory    -> Types::DataPipeline::TransformInventoryResult
#   transform_customers    -> Types::DataPipeline::TransformCustomersResult
#   aggregate_metrics      -> Types::DataPipeline::AggregateMetricsResult
#   generate_insights      -> Types::DataPipeline::GenerateInsightsResult
module DataPipeline
  module Service
    SAMPLE_PRODUCTS = %w[Widget-A Gadget-B Doohickey-C Thingamajig-D].freeze
    REGIONS = %w[northeast southeast midwest west international].freeze
    WAREHOUSES = %w[WH-EAST WH-WEST WH-CENTRAL WH-SOUTH].freeze
    INVENTORY_CATEGORIES = %w[electronics clothing home_garden sports food_beverage].freeze
    CUSTOMER_SEGMENTS = %w[new_customer returning loyal churned at_risk].freeze
    CUSTOMER_TIERS = %w[bronze silver gold platinum].freeze
    ACQUISITION_CHANNELS = %w[organic paid_search social referral direct email].freeze

    module_function

    # ── Extract functions ──────────────────────────────────────────────

    def extract_sales_data(source:, date_range_start:, date_range_end:, granularity:)
      raise TaskerCore::Errors::PermanentError.new(
        'Source system is required',
        error_code: 'MISSING_SOURCE'
      ) if source.blank?

      raise TaskerCore::Errors::RetryableError.new(
        "Source system '#{source}' is temporarily unavailable"
      ) if source == 'staging' && rand < 0.1

      start_date = date_range_start || (Date.current - 30).iso8601
      end_date = date_range_end || Date.current.iso8601

      record_count = rand(150..500)
      records = record_count.times.filter_map do |_i|
        region = REGIONS.sample
        product = SAMPLE_PRODUCTS.sample
        quantity = rand(1..50)
        unit_price = rand(9.99..299.99).round(2)
        discount = rand < 0.3 ? rand(0.05..0.25).round(2) : 0.0
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
      end

      total_revenue = records.sum { |r| r[:revenue] }

      Types::DataPipeline::ExtractSalesResult.new(
        source: source,
        extraction_id: "ext_sales_#{SecureRandom.hex(8)}",
        date_range: { start_date: start_date, end_date: end_date },
        record_count: records.size,
        records: records,
        total_amount: total_revenue.round(2),
        total_revenue: total_revenue.round(2),
        extracted_at: Time.current.iso8601
      )
    end

    def extract_inventory_data(source:, filters:)
      raise TaskerCore::Errors::PermanentError.new(
        'Source system is required',
        error_code: 'MISSING_SOURCE'
      ) if source.blank?

      category_filter = filters&.dig('product_category')

      record_count = rand(80..200)
      records = record_count.times.filter_map do |_i|
        category = INVENTORY_CATEGORIES.sample
        next if category_filter.present? && category != category_filter

        sku = "SKU-#{category[0..2].upcase}-#{SecureRandom.hex(3).upcase}"
        on_hand = rand(0..1000)
        reorder_point = rand(10..100)
        unit_cost = rand(2.50..150.00).round(2)

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
      end

      total_value = records.sum { |r| r[:total_value] }
      items_needing_reorder = records.count { |r| r[:needs_reorder] }

      Types::DataPipeline::ExtractInventoryResult.new(
        source: source,
        extraction_id: "ext_inv_#{SecureRandom.hex(8)}",
        record_count: records.size,
        records: records,
        total_quantity: records.sum { |r| r[:on_hand_quantity] },
        warehouses: records.map { |r| r[:warehouse] }.uniq,
        products_tracked: records.map { |r| r[:sku] }.uniq.count,
        total_inventory_value: total_value.round(2),
        items_needing_reorder: items_needing_reorder,
        warehouses_covered: records.map { |r| r[:warehouse] }.uniq,
        extracted_at: Time.current.iso8601
      )
    end

    def extract_customer_data(source:, date_range_start:)
      raise TaskerCore::Errors::PermanentError.new(
        'Source system is required',
        error_code: 'MISSING_SOURCE'
      ) if source.blank?

      _start_date = date_range_start || (Date.current - 30).iso8601

      record_count = rand(100..300)
      records = record_count.times.map do |_i|
        customer_id = "CUST-#{SecureRandom.hex(6).upcase}"
        segment = CUSTOMER_SEGMENTS.sample
        lifetime_value = rand(25.0..5000.0).round(2)
        order_count = rand(1..50)
        last_order_days_ago = rand(1..365)

        {
          customer_id: customer_id,
          segment: segment,
          tier: CUSTOMER_TIERS.sample,
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
      segment_distribution = records.group_by { |r| r[:segment] }.transform_values(&:count)
      tier_breakdown = records.group_by { |r| r[:tier] }.transform_values(&:count)

      Types::DataPipeline::ExtractCustomerResult.new(
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
      )
    end

    # ── Transform functions ────────────────────────────────────────────

    def transform_sales(sales_data:)
      raise TaskerCore::Errors::PermanentError.new(
        'Sales extraction data not available',
        error_code: 'MISSING_EXTRACTION'
      ) if sales_data.nil?

      records = sales_data[:records] || sales_data['records'] || []

      raise TaskerCore::Errors::PermanentError.new(
        'No sales records to transform',
        error_code: 'EMPTY_DATASET'
      ) if records.empty?

      # Group by product
      by_product = records.group_by { |r| r['product'] || r[:product] }
      product_metrics = by_product.map do |product, sales|
        revenue = sales.sum { |s| (s['revenue'] || s[:revenue]).to_f }
        qty = sales.sum { |s| (s['quantity'] || s[:quantity]).to_i }
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
      by_region = records.group_by { |r| r['region'] || r[:region] }
      region_metrics = by_region.map do |region, sales|
        revenue = sales.sum { |s| (s['revenue'] || s[:revenue]).to_f }
        {
          region: region,
          total_revenue: revenue.round(2),
          transaction_count: sales.size,
          average_order_value: (revenue / sales.size).round(2)
        }
      end.sort_by { |m| -m[:total_revenue] }

      # Group by channel
      by_channel = records.group_by { |r| r['channel'] || r[:channel] }
      channel_metrics = by_channel.map do |channel, sales|
        revenue = sales.sum { |s| (s['revenue'] || s[:revenue]).to_f }
        {
          channel: channel,
          total_revenue: revenue.round(2),
          transaction_count: sales.size,
          revenue_share: 0.0
        }
      end
      total_revenue = channel_metrics.sum { |m| m[:total_revenue] }
      channel_metrics.each { |m| m[:revenue_share] = ((m[:total_revenue] / total_revenue) * 100).round(1) }

      # Discount analysis
      discounted = records.select { |r| (r['discount_rate'] || r[:discount_rate]).to_f > 0 }
      avg_discount = discounted.empty? ? 0.0 : (discounted.sum { |r| (r['discount_rate'] || r[:discount_rate]).to_f } / discounted.size).round(3)

      # Build daily_sales and product_sales for source compatibility
      daily_sales = records.group_by { |r| r['sale_date'] || r[:sale_date] }
                           .transform_values do |day_records|
                             {
                               total_amount: day_records.sum { |r| (r['revenue'] || r[:revenue]).to_f },
                               order_count: day_records.count,
                               avg_order_value: day_records.sum { |r| (r['revenue'] || r[:revenue]).to_f } / day_records.count.to_f
                             }
      end

      product_sales = records.group_by { |r| r['product'] || r[:product] }
                             .transform_values do |product_records|
                               {
                                 total_quantity: product_records.sum { |r| (r['quantity'] || r[:quantity]).to_i },
                                 total_revenue: product_records.sum { |r| (r['revenue'] || r[:revenue]).to_f },
                                 order_count: product_records.count
                               }
      end

      Types::DataPipeline::TransformSalesResult.new(
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
        top_product: product_metrics.first&.dig(:product),
        top_region: region_metrics.first&.dig(:region),
        transformed_at: Time.current.iso8601
      )
    end

    def transform_inventory(inventory_data:)
      raise TaskerCore::Errors::PermanentError.new(
        'Inventory extraction data not available',
        error_code: 'MISSING_EXTRACTION'
      ) if inventory_data.nil?

      records = inventory_data[:records] || inventory_data['records'] || []

      raise TaskerCore::Errors::PermanentError.new(
        'No inventory records to transform',
        error_code: 'EMPTY_DATASET'
      ) if records.empty?

      # Group by category
      by_category = records.group_by { |r| r['category'] || r[:category] }
      category_metrics = by_category.map do |category, items|
        total_value = items.sum { |i| (i['total_value'] || i[:total_value]).to_f }
        total_on_hand = items.sum { |i| (i['on_hand_quantity'] || i[:on_hand_quantity]).to_i }
        needing_reorder = items.count { |i| i['needs_reorder'] || i[:needs_reorder] }
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
      by_warehouse = records.group_by { |r| r['warehouse'] || r[:warehouse] }
      warehouse_metrics = by_warehouse.map do |warehouse, items|
        total_value = items.sum { |i| (i['total_value'] || i[:total_value]).to_f }
        {
          warehouse: warehouse,
          sku_count: items.size,
          total_on_hand: items.sum { |i| (i['on_hand_quantity'] || i[:on_hand_quantity]).to_i },
          total_value: total_value.round(2),
          utilization_score: rand(0.5..0.95).round(2)
        }
      end

      # Overall metrics
      total_inventory_value = records.sum { |r| (r['total_value'] || r[:total_value]).to_f }
      total_skus = records.size
      avg_lead_time = (records.sum { |r| (r['supplier_lead_days'] || r[:supplier_lead_days]).to_i }.to_f / total_skus).round(1)
      stockout_risk = records.count { |r| (r['on_hand_quantity'] || r[:on_hand_quantity]).to_i == 0 }

      # Turnover estimation (simplified)
      turnover_rates = category_metrics.map do |cm|
        { category: cm[:category], estimated_turnover: rand(2.0..12.0).round(1) }
      end

      # Build warehouse_summary and product_inventory for source compatibility
      warehouse_summary = by_warehouse.transform_values do |wh_records|
        {
          total_quantity: wh_records.sum { |r| (r['on_hand_quantity'] || r[:on_hand_quantity]).to_i },
          product_count: wh_records.map { |r| r['sku'] || r[:sku] }.uniq.count,
          reorder_alerts: wh_records.count { |r| r['needs_reorder'] || r[:needs_reorder] }
        }
      end

      product_inventory = records.group_by { |r| r['sku'] || r[:sku] }.transform_values do |product_records|
        total_qty = product_records.sum { |r| (r['on_hand_quantity'] || r[:on_hand_quantity]).to_i }
        total_reorder = product_records.sum { |r| (r['reorder_point'] || r[:reorder_point]).to_i }
        {
          total_quantity: total_qty,
          warehouse_count: product_records.map { |r| r['warehouse'] || r[:warehouse] }.uniq.count,
          needs_reorder: total_qty < total_reorder
        }
      end

      reorder_alerts_count = product_inventory.count { |_id, data| data[:needs_reorder] }
      total_quantity_on_hand = records.sum { |r| (r['on_hand_quantity'] || r[:on_hand_quantity]).to_i }

      Types::DataPipeline::TransformInventoryResult.new(
        record_count: records.size,
        warehouse_summary: warehouse_summary,
        product_inventory: product_inventory,
        total_quantity_on_hand: total_quantity_on_hand,
        reorder_alerts: reorder_alerts_count,
        transformation_type: 'inventory_analytics',
        source: 'extract_inventory_data',
        transform_id: "tfm_inv_#{SecureRandom.hex(8)}",
        source_record_count: records.size,
        category_metrics: category_metrics,
        warehouse_metrics: warehouse_metrics,
        total_inventory_value: total_inventory_value.round(2),
        total_skus: total_skus,
        transformed_at: Time.current.iso8601
      )
    end

    def transform_customers(customer_data:)
      raise TaskerCore::Errors::PermanentError.new(
        'Customer extraction data not available',
        error_code: 'MISSING_EXTRACTION'
      ) if customer_data.nil?

      records = customer_data[:records] || customer_data['records'] || []

      raise TaskerCore::Errors::PermanentError.new(
        'No customer records to transform',
        error_code: 'EMPTY_DATASET'
      ) if records.empty?

      # Segment analysis
      by_segment = records.group_by { |r| r['segment'] || r[:segment] }
      segment_metrics = by_segment.map do |segment, customers|
        avg_ltv = (customers.sum { |c| (c['lifetime_value'] || c[:lifetime_value]).to_f } / customers.size).round(2)
        avg_orders = (customers.sum { |c| (c['total_orders'] || c[:total_orders]).to_i }.to_f / customers.size).round(1)
        engagement = (customers.count { |c| c['email_engaged'] || c[:email_engaged] }.to_f / customers.size * 100).round(1)
        {
          segment: segment,
          customer_count: customers.size,
          percentage_of_total: ((customers.size.to_f / records.size) * 100).round(1),
          average_lifetime_value: avg_ltv,
          average_orders: avg_orders,
          email_engagement_rate: engagement,
          average_days_since_order: (customers.sum { |c| (c['days_since_last_order'] || c[:days_since_last_order]).to_i }.to_f / customers.size).round(0)
        }
      end.sort_by { |m| -m[:average_lifetime_value] }

      # Tier analysis
      by_tier = records.group_by { |r| r['tier'] || r[:tier] }
      tier_metrics = by_tier.map do |tier, customers|
        total_ltv = customers.sum { |c| (c['lifetime_value'] || c[:lifetime_value]).to_f }
        {
          tier: tier,
          customer_count: customers.size,
          total_lifetime_value: total_ltv.round(2),
          average_lifetime_value: (total_ltv / customers.size).round(2)
        }
      end.sort_by { |m| -m[:total_lifetime_value] }

      # Acquisition channel analysis
      by_channel = records.group_by { |r| r['acquisition_channel'] || r[:acquisition_channel] }
      channel_metrics = by_channel.map do |channel, customers|
        avg_ltv = (customers.sum { |c| (c['lifetime_value'] || c[:lifetime_value]).to_f } / customers.size).round(2)
        {
          channel: channel,
          customer_count: customers.size,
          average_lifetime_value: avg_ltv,
          retention_estimate: rand(0.3..0.85).round(2)
        }
      end.sort_by { |m| -m[:average_lifetime_value] }

      # Cohort analysis (simplified by region)
      by_region = records.group_by { |r| r['region'] || r[:region] }
      region_metrics = by_region.map do |region, customers|
        {
          region: region,
          customer_count: customers.size,
          average_ltv: (customers.sum { |c| (c['lifetime_value'] || c[:lifetime_value]).to_f } / customers.size).round(2)
        }
      end

      # Churn risk assessment
      at_risk = records.select { |r| (r['days_since_last_order'] || r[:days_since_last_order]).to_i > 90 }
      churn_rate = ((at_risk.size.to_f / records.size) * 100).round(1)

      # Build tier_analysis and value_segments for source compatibility
      tier_analysis = by_tier.transform_values do |tier_records|
        {
          customer_count: tier_records.count,
          total_lifetime_value: tier_records.sum { |r| (r['lifetime_value'] || r[:lifetime_value]).to_f },
          avg_lifetime_value: tier_records.sum { |r| (r['lifetime_value'] || r[:lifetime_value]).to_f } / tier_records.count.to_f
        }
      end

      total_lifetime_value = records.sum { |r| (r['lifetime_value'] || r[:lifetime_value]).to_f }
      avg_customer_value = total_lifetime_value / records.count.to_f

      value_segments = {
        high_value: records.count { |r| (r['lifetime_value'] || r[:lifetime_value]).to_f >= 10_000 },
        medium_value: records.count { |r| (r['lifetime_value'] || r[:lifetime_value]).to_f.between?(1000, 9999) },
        low_value: records.count { |r| (r['lifetime_value'] || r[:lifetime_value]).to_f < 1000 }
      }

      Types::DataPipeline::TransformCustomersResult.new(
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
        overall_engagement_rate: (records.count { |r| r['email_engaged'] || r[:email_engaged] }.to_f / records.size * 100).round(1),
        transformed_at: Time.current.iso8601
      )
    end

    # ── Aggregation functions ──────────────────────────────────────────

    def aggregate_metrics(sales_transform:, inventory_transform:, customer_transform:)
      raise TaskerCore::Errors::PermanentError.new(
        'One or more transform results are missing',
        error_code: 'MISSING_TRANSFORMS'
      ) if sales_transform.nil? || inventory_transform.nil? || customer_transform.nil?

      total_revenue = (sales_transform['total_revenue'] || sales_transform[:total_revenue]).to_f
      total_inventory_value = (inventory_transform['total_inventory_value'] || inventory_transform[:total_inventory_value]).to_f
      total_customers = (customer_transform['source_record_count'] || customer_transform[:source_record_count]).to_i

      # Cross-source metrics
      revenue_per_customer = total_customers > 0 ? (total_revenue / total_customers).round(2) : 0.0
      inventory_to_revenue_ratio = total_revenue > 0 ? (total_inventory_value / total_revenue).round(3) : 0.0

      # Sales velocity
      top_product = sales_transform['top_product'] || sales_transform[:top_product]
      top_region = sales_transform['top_region'] || sales_transform[:top_region]

      # Inventory health
      overall_reorder_rate = (inventory_transform['overall_reorder_rate'] || inventory_transform[:overall_reorder_rate]).to_f
      stockout_risk = (inventory_transform['stockout_risk_count'] || inventory_transform[:stockout_risk_count]).to_i
      avg_lead_time = (inventory_transform['average_supplier_lead_days'] || inventory_transform[:average_supplier_lead_days]).to_f

      # Customer health
      churn_risk_rate = (customer_transform['churn_risk_rate'] || customer_transform[:churn_risk_rate]).to_f
      engagement_rate = (customer_transform['overall_engagement_rate'] || customer_transform[:overall_engagement_rate]).to_f

      # Composite scores (0-100)
      sales_health = [100, [(total_revenue / 10_000.0 * 100).round(0), 0].max].min
      inventory_health = [100, (100 - overall_reorder_rate - stockout_risk).round(0)].max
      customer_health = [100, (engagement_rate * (1 - churn_risk_rate / 100)).round(0)].max
      overall_health = ((sales_health + inventory_health + customer_health) / 3.0).round(0)

      # Category cross-reference
      sales_by_channel = (sales_transform['channel_metrics'] || sales_transform[:channel_metrics] || []).map do |cm|
        { channel: cm['channel'] || cm[:channel], revenue: cm['total_revenue'] || cm[:total_revenue], share: cm['revenue_share'] || cm[:revenue_share] }
      end

      customer_by_segment = (customer_transform['segment_metrics'] || customer_transform[:segment_metrics] || []).map do |sm|
        { segment: sm['segment'] || sm[:segment], count: sm['customer_count'] || sm[:customer_count], avg_ltv: sm['average_lifetime_value'] || sm[:average_lifetime_value] }
      end

      # Source-compatible flat keys
      sales_record_count = sales_transform['record_count'] || sales_transform[:record_count] || sales_transform['source_record_count'] || sales_transform[:source_record_count] || 0
      total_ltv = customer_transform['total_lifetime_value'] || customer_transform[:total_lifetime_value] || 0
      inventory_reorder_alerts = inventory_transform['reorder_alerts'] || inventory_transform[:reorder_alerts] || 0
      total_inventory_quantity = inventory_transform['total_quantity_on_hand'] || inventory_transform[:total_quantity_on_hand] || total_inventory_value

      Types::DataPipeline::AggregateMetricsResult.new(
        total_revenue: total_revenue,
        total_inventory_quantity: total_inventory_quantity,
        total_customers: total_customers,
        total_customer_lifetime_value: total_ltv,
        sales_transactions: sales_record_count,
        inventory_reorder_alerts: inventory_reorder_alerts,
        revenue_per_customer: revenue_per_customer,
        inventory_turnover_indicator: inventory_to_revenue_ratio,
        aggregation_complete: true,
        sources_included: 3,
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
          sales_records: sales_transform['source_record_count'] || sales_transform[:source_record_count],
          inventory_records: inventory_transform['source_record_count'] || inventory_transform[:source_record_count],
          customer_records: customer_transform['source_record_count'] || customer_transform[:source_record_count]
        },
        aggregated_at: Time.current.iso8601
      )
    end

    # ── Insight functions ──────────────────────────────────────────────

    def generate_insights(aggregation:)
      raise TaskerCore::Errors::PermanentError.new(
        'Aggregated metrics not available',
        error_code: 'MISSING_AGGREGATION'
      ) if aggregation.nil?

      health_scores = aggregation['health_scores'] || aggregation[:health_scores] || {}
      highlights = aggregation['highlights'] || aggregation[:highlights] || {}
      summary = aggregation['summary'] || aggregation[:summary] || {}

      overall_health = (health_scores['overall'] || health_scores[:overall]).to_i
      sales_health = (health_scores['sales'] || health_scores[:sales]).to_i
      _inventory_health = (health_scores['inventory'] || health_scores[:inventory]).to_i
      _customer_health = (health_scores['customer'] || health_scores[:customer]).to_i
      churn_risk = (highlights['churn_risk_rate'] || highlights[:churn_risk_rate]).to_f
      reorder_rate = (highlights['reorder_rate'] || highlights[:reorder_rate]).to_f

      insights = []
      recommendations = []

      # Sales insights
      if sales_health < 50
        insights << {
          category: 'sales',
          severity: 'critical',
          finding: 'Revenue is significantly below target thresholds',
          impact: 'Revenue shortfall may affect quarterly projections'
        }
        recommendations << {
          priority: 'high',
          action: 'Launch promotional campaign targeting top-performing channels',
          expected_impact: 'Potential 15-25% revenue increase'
        }
      elsif sales_health < 75
        insights << {
          category: 'sales',
          severity: 'warning',
          finding: 'Revenue growth is below optimal levels',
          impact: 'May need intervention to meet growth targets'
        }
      else
        insights << {
          category: 'sales',
          severity: 'positive',
          finding: 'Revenue performance is healthy',
          impact: "Top product: #{highlights['top_product'] || highlights[:top_product]}, Top region: #{highlights['top_region'] || highlights[:top_region]}"
        }
      end

      # Inventory insights
      if reorder_rate > 30
        insights << {
          category: 'inventory',
          severity: 'critical',
          finding: "#{reorder_rate}% of SKUs need reordering with #{highlights['stockout_risk_items'] || highlights[:stockout_risk_items]} at stockout risk",
          impact: 'High risk of lost sales due to stockouts'
        }
        recommendations << {
          priority: 'urgent',
          action: 'Initiate emergency reorder for critical SKUs',
          expected_impact: 'Prevent estimated revenue loss from stockouts'
        }
      elsif reorder_rate > 15
        insights << {
          category: 'inventory',
          severity: 'warning',
          finding: "#{reorder_rate}% of SKUs approaching reorder thresholds",
          impact: 'Proactive reordering recommended within 2 weeks'
        }
      end

      # Customer insights
      if churn_risk > 25
        insights << {
          category: 'customer',
          severity: 'critical',
          finding: "Churn risk at #{churn_risk}% - significant customer attrition detected",
          impact: 'Customer lifetime value at risk'
        }
        recommendations << {
          priority: 'high',
          action: 'Deploy win-back campaign targeting at-risk customers',
          expected_impact: "Potential to recover #{(churn_risk * 0.3).round(1)}% of at-risk customers"
        }
      elsif churn_risk > 15
        insights << {
          category: 'customer',
          severity: 'warning',
          finding: "Churn risk at #{churn_risk}% - above normal threshold",
          impact: 'Customer engagement declining in some segments'
        }
        recommendations << {
          priority: 'medium',
          action: 'Increase engagement touchpoints for low-activity customers',
          expected_impact: 'Improve retention by 5-10%'
        }
      end

      # Cross-source insight
      inv_to_rev = (summary['inventory_to_revenue_ratio'] || summary[:inventory_to_revenue_ratio]).to_f
      if inv_to_rev > 3.0
        insights << {
          category: 'operations',
          severity: 'warning',
          finding: "Inventory-to-revenue ratio of #{inv_to_rev} suggests overstocking",
          impact: 'Capital tied up in excess inventory'
        }
        recommendations << {
          priority: 'medium',
          action: 'Review slow-moving inventory and consider clearance pricing',
          expected_impact: 'Free up working capital and reduce carrying costs'
        }
      end

      # Overall business health assessment
      health_label = case overall_health
                     when 80..100 then 'excellent'
                     when 60..79  then 'good'
                     when 40..59  then 'fair'
                     when 20..39  then 'poor'
                     else 'critical'
                     end

      report_id = "RPT-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"

      health_score_obj = {
        score: overall_health,
        max_score: 100,
        rating: health_label.capitalize
      }

      Types::DataPipeline::GenerateInsightsResult.new(
        insights: insights,
        health_score: health_score_obj,
        total_metrics_analyzed: aggregation.is_a?(Hash) ? aggregation.keys.count : 0,
        pipeline_complete: true,
        generated_at: Time.current.iso8601,
        report_id: report_id,
        business_health: health_label,
        overall_score: overall_health,
        component_scores: health_scores,
        recommendations: recommendations.sort_by { |r| { 'urgent' => 0, 'high' => 1, 'medium' => 2, 'low' => 3 }[r[:priority]] || 4 },
        insight_count: insights.size,
        recommendation_count: recommendations.size,
        critical_items: insights.count { |i| i[:severity] == 'critical' },
        data_freshness: aggregation['aggregated_at'] || aggregation[:aggregated_at]
      )
    end
  end
end
