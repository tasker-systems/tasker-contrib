module DataPipeline
  module StepHandlers
    class GenerateInsightsHandler < TaskerCore::StepHandler::Base
      def call(context)
        aggregation = context.get_dependency_field('aggregate_metrics', ['result'])

        raise TaskerCore::Errors::PermanentError.new(
          'Aggregated metrics not available',
          error_code: 'MISSING_AGGREGATION'
        ) if aggregation.nil?

        health_scores = aggregation['health_scores'] || {}
        highlights = aggregation['highlights'] || {}
        summary = aggregation['summary'] || {}

        overall_health = health_scores['overall'].to_i
        sales_health = health_scores['sales'].to_i
        inventory_health = health_scores['inventory'].to_i
        customer_health = health_scores['customer'].to_i
        churn_risk = highlights['churn_risk_rate'].to_f
        reorder_rate = highlights['reorder_rate'].to_f

        # Generate actionable insights based on metrics
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
            impact: "Top product: #{highlights['top_product']}, Top region: #{highlights['top_region']}"
          }
        end

        # Inventory insights
        if reorder_rate > 30
          insights << {
            category: 'inventory',
            severity: 'critical',
            finding: "#{reorder_rate}% of SKUs need reordering with #{highlights['stockout_risk_items']} at stockout risk",
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
        inv_to_rev = summary['inventory_to_revenue_ratio'].to_f
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

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            report_id: report_id,
            business_health: health_label,
            overall_score: overall_health,
            component_scores: health_scores,
            insights: insights,
            recommendations: recommendations.sort_by { |r| { 'urgent' => 0, 'high' => 1, 'medium' => 2, 'low' => 3 }[r[:priority]] || 4 },
            insight_count: insights.size,
            recommendation_count: recommendations.size,
            critical_items: insights.count { |i| i[:severity] == 'critical' },
            data_freshness: aggregation['aggregated_at'],
            generated_at: Time.current.iso8601
          },
          metadata: {
            handler: self.class.name,
            report_id: report_id,
            health_label: health_label,
            overall_score: overall_health,
            insight_count: insights.size
          }
        )
      end
    end
  end
end
