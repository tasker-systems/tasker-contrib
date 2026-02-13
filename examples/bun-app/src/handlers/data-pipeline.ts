import {
  StepHandler,
  type StepContext,
  type StepHandlerResult,
  ErrorType,
} from '@tasker-systems/tasker';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface DataRecord {
  id: string;
  value: number;
  category: string;
  timestamp: string;
}

// ---------------------------------------------------------------------------
// Step 1: ExtractSalesData (parallel with steps 2 and 3)
// ---------------------------------------------------------------------------

export class ExtractSalesDataHandler extends StepHandler {
  static handlerName = 'DataPipeline.StepHandlers.ExtractSalesDataHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const sources = context.getInput<string[]>('sources') || [];
      const dateRange = context.getInput<{ start: string; end: string }>('date_range');

      // Simulate extracting sales data from source systems
      const recordCount = Math.floor(Math.random() * 500) + 100;
      const records: DataRecord[] = Array.from({ length: Math.min(recordCount, 20) }, (_, i) => ({
        id: `sale-${crypto.randomUUID().substring(0, 8)}`,
        value: Math.round(Math.random() * 1000 * 100) / 100,
        category: ['electronics', 'clothing', 'food', 'home'][Math.floor(Math.random() * 4)],
        timestamp: new Date(
          Date.now() - Math.random() * 30 * 24 * 60 * 60 * 1000,
        ).toISOString(),
      }));

      const totalRevenue = records.reduce((sum, r) => sum + r.value, 0);

      return this.success(
        {
          records: records,
          extracted_at: new Date().toISOString(),
          source: 'SalesDatabase',
          total_amount: Math.round(totalRevenue * 100) / 100,
          date_range: dateRange || { start: 'unknown', end: 'unknown' },
          record_count: recordCount,
          extraction_sources: sources.filter((s) => s.includes('sales')).length || 1,
          schema_version: '2.1',
        },
        { extraction_time_ms: Math.random() * 2000 + 500, rows_scanned: recordCount * 3 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.RETRYABLE_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 2: ExtractInventoryData (parallel with steps 1 and 3)
// ---------------------------------------------------------------------------

export class ExtractInventoryDataHandler extends StepHandler {
  static handlerName = 'DataPipeline.StepHandlers.ExtractInventoryDataHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const parameters = context.getInput<Record<string, unknown>>('parameters') || {};

      // Simulate extracting inventory snapshots
      const warehouseCount = 4;
      const skuCount = Math.floor(Math.random() * 200) + 50;
      const warehouses = ['east-1', 'west-1', 'central-1', 'south-1'];

      const inventorySnapshot = warehouses.map((wh) => ({
        warehouse_id: wh,
        total_skus: Math.floor(skuCount / warehouseCount) + Math.floor(Math.random() * 20),
        total_units: Math.floor(Math.random() * 10000) + 1000,
        low_stock_skus: Math.floor(Math.random() * 10),
        out_of_stock_skus: Math.floor(Math.random() * 3),
      }));

      const totalUnits = inventorySnapshot.reduce((sum, wh) => sum + wh.total_units, 0);

      return this.success(
        {
          records: inventorySnapshot,
          extracted_at: new Date().toISOString(),
          source: 'InventorySystem',
          total_quantity: totalUnits,
          warehouses: warehouses,
          products_tracked: skuCount,
          record_count: skuCount,
          warehouse_count: warehouseCount,
          include_archived: parameters.include_archived || false,
        },
        { extraction_time_ms: Math.random() * 1500 + 300 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.RETRYABLE_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 3: ExtractCustomerData (parallel with steps 1 and 2)
// ---------------------------------------------------------------------------

export class ExtractCustomerDataHandler extends StepHandler {
  static handlerName = 'DataPipeline.StepHandlers.ExtractCustomerDataHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const dateRange = context.getInput<{ start: string; end: string }>('date_range');

      // Simulate extracting customer activity data
      const totalCustomers = Math.floor(Math.random() * 5000) + 1000;
      const activeCustomers = Math.floor(totalCustomers * (0.3 + Math.random() * 0.4));
      const newCustomers = Math.floor(Math.random() * 200) + 20;

      const segmentBreakdown = {
        premium: Math.floor(totalCustomers * 0.05),
        standard: Math.floor(totalCustomers * 0.35),
        basic: Math.floor(totalCustomers * 0.45),
        trial: Math.floor(totalCustomers * 0.15),
      };

      const regionBreakdown = {
        north_america: Math.floor(totalCustomers * 0.45),
        europe: Math.floor(totalCustomers * 0.30),
        asia_pacific: Math.floor(totalCustomers * 0.15),
        other: Math.floor(totalCustomers * 0.10),
      };

      // Build simulated customer records for downstream consumption
      const records = Array.from({ length: Math.min(totalCustomers, 10) }, (_, i) => ({
        customer_id: `CUST-${String(i + 1).padStart(3, '0')}`,
        name: `Customer ${i + 1}`,
        tier: Object.keys(segmentBreakdown)[i % Object.keys(segmentBreakdown).length],
        lifetime_value: Math.round((Math.random() * 10000 + 500) * 100) / 100,
        join_date: new Date(Date.now() - Math.random() * 365 * 24 * 60 * 60 * 1000).toISOString().substring(0, 10),
      }));

      const totalLifetimeValue = records.reduce((sum, r) => sum + r.lifetime_value, 0);

      return this.success(
        {
          records: records,
          extracted_at: new Date().toISOString(),
          source: 'CRMSystem',
          total_customers: totalCustomers,
          total_lifetime_value: Math.round(totalLifetimeValue * 100) / 100,
          tier_breakdown: segmentBreakdown,
          avg_lifetime_value: Math.round((totalLifetimeValue / records.length) * 100) / 100,
          active_customers: activeCustomers,
          new_customers_in_period: newCustomers,
          churn_count: Math.floor(Math.random() * 50) + 5,
          region_breakdown: regionBreakdown,
          date_range: dateRange || { start: 'unknown', end: 'unknown' },
        },
        { extraction_time_ms: Math.random() * 1800 + 400, api_calls_made: 3 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.RETRYABLE_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 4: TransformSales (depends on ExtractSalesData)
// ---------------------------------------------------------------------------

export class TransformSalesHandler extends StepHandler {
  static handlerName = 'DataPipeline.StepHandlers.TransformSalesHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const extractResults = context.getDependencyResult('extract_sales_data') as Record<string, unknown>;

      if (!extractResults) {
        return this.failure('Sales extraction results not found', ErrorType.PERMANENT_ERROR, false);
      }

      const rawRecords = (extractResults.records || []) as DataRecord[];
      const totalAmount = extractResults.total_amount as number;

      // Group by category to build product_sales equivalent
      const productSales: Record<string, { total_quantity: number; total_revenue: number; order_count: number }> = {};
      for (const record of rawRecords) {
        if (!productSales[record.category]) {
          productSales[record.category] = { total_quantity: 0, total_revenue: 0, order_count: 0 };
        }
        productSales[record.category].order_count += 1;
        productSales[record.category].total_revenue += record.value;
        productSales[record.category].total_quantity += 1;
      }
      for (const cat of Object.keys(productSales)) {
        productSales[cat].total_revenue = Math.round(productSales[cat].total_revenue * 100) / 100;
      }

      // Calculate time-series aggregation (daily totals)
      const dailySales: Record<string, { total_amount: number; order_count: number; avg_order_value: number }> = {};
      for (const record of rawRecords) {
        const day = record.timestamp.substring(0, 10);
        if (!dailySales[day]) {
          dailySales[day] = { total_amount: 0, order_count: 0, avg_order_value: 0 };
        }
        dailySales[day].total_amount += record.value;
        dailySales[day].order_count += 1;
      }
      for (const day of Object.keys(dailySales)) {
        dailySales[day].avg_order_value =
          Math.round((dailySales[day].total_amount / dailySales[day].order_count) * 100) / 100;
      }

      const totalRevenue = totalAmount || rawRecords.reduce((sum, r) => sum + r.value, 0);

      return this.success(
        {
          record_count: rawRecords.length,
          daily_sales: dailySales,
          product_sales: productSales,
          total_revenue: totalRevenue,
          transformation_type: 'sales_analytics',
          source: 'extract_sales_data',
          unique_categories: Object.keys(productSales).length,
          avg_transaction_value: rawRecords.length > 0 ? Math.round((totalRevenue / rawRecords.length) * 100) / 100 : 0,
          transformed_at: new Date().toISOString(),
        },
        { transform_time_ms: Math.random() * 300 + 50, records_processed: rawRecords.length },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 5: TransformInventory (depends on ExtractInventoryData)
// ---------------------------------------------------------------------------

export class TransformInventoryHandler extends StepHandler {
  static handlerName = 'DataPipeline.StepHandlers.TransformInventoryHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const extractResults = context.getDependencyResult('extract_inventory_data') as Record<string, unknown>;

      if (!extractResults) {
        return this.failure('Inventory extraction results not found', ErrorType.PERMANENT_ERROR, false);
      }

      const rawRecords = (extractResults.records || []) as Array<{
        warehouse_id: string;
        total_skus: number;
        total_units: number;
        low_stock_skus: number;
        out_of_stock_skus: number;
      }>;

      // Build warehouse_summary (keyed by warehouse)
      const warehouseSummary: Record<string, { total_quantity: number; product_count: number; reorder_alerts: number }> = {};
      for (const wh of rawRecords) {
        warehouseSummary[wh.warehouse_id] = {
          total_quantity: wh.total_units,
          product_count: wh.total_skus,
          reorder_alerts: wh.low_stock_skus + wh.out_of_stock_skus,
        };
      }

      // Build product_inventory (simulated per-product aggregation)
      const productInventory: Record<string, { total_quantity: number; warehouse_count: number; needs_reorder: boolean }> = {};
      for (const wh of rawRecords) {
        const productId = wh.warehouse_id; // Use warehouse_id as proxy for product grouping
        productInventory[productId] = {
          total_quantity: wh.total_units,
          warehouse_count: 1,
          needs_reorder: wh.low_stock_skus > 0 || wh.out_of_stock_skus > 0,
        };
      }

      const totalQuantityOnHand = rawRecords.reduce((sum, wh) => sum + wh.total_units, 0);
      const reorderAlerts = Object.values(productInventory).filter(p => p.needs_reorder).length;

      return this.success(
        {
          record_count: rawRecords.length,
          warehouse_summary: warehouseSummary,
          product_inventory: productInventory,
          total_quantity_on_hand: totalQuantityOnHand,
          reorder_alerts: reorderAlerts,
          transformation_type: 'inventory_analytics',
          source: 'extract_inventory_data',
          transformed_at: new Date().toISOString(),
        },
        { transform_time_ms: Math.random() * 200 + 30 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 6: TransformCustomer (depends on ExtractCustomerData)
// ---------------------------------------------------------------------------

export class TransformCustomerHandler extends StepHandler {
  static handlerName = 'DataPipeline.StepHandlers.TransformCustomersHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const extractResults = context.getDependencyResult('extract_customer_data') as Record<string, unknown>;

      if (!extractResults) {
        return this.failure('Customer extraction results not found', ErrorType.PERMANENT_ERROR, false);
      }

      const rawRecords = (extractResults.records || []) as Array<{
        customer_id: string;
        name: string;
        tier: string;
        lifetime_value: number;
        join_date: string;
      }>;

      // Group by tier for tier_analysis
      const tierGroups = new Map<string, Array<{ lifetime_value: number }>>();
      for (const record of rawRecords) {
        const existing = tierGroups.get(record.tier) || [];
        existing.push(record);
        tierGroups.set(record.tier, existing);
      }

      const tierAnalysis: Record<string, { customer_count: number; total_lifetime_value: number; avg_lifetime_value: number }> = {};
      for (const [tier, tierRecords] of tierGroups) {
        const totalLtv = tierRecords.reduce((sum, r) => sum + r.lifetime_value, 0);
        tierAnalysis[tier] = {
          customer_count: tierRecords.length,
          total_lifetime_value: Math.round(totalLtv * 100) / 100,
          avg_lifetime_value: Math.round((totalLtv / tierRecords.length) * 100) / 100,
        };
      }

      // Value segmentation
      const valueSegments = {
        high_value: rawRecords.filter(r => r.lifetime_value >= 10000).length,
        medium_value: rawRecords.filter(r => r.lifetime_value >= 1000 && r.lifetime_value < 10000).length,
        low_value: rawRecords.filter(r => r.lifetime_value < 1000).length,
      };

      const totalLifetimeValue = rawRecords.reduce((sum, r) => sum + r.lifetime_value, 0);
      const avgCustomerValue = rawRecords.length > 0 ? totalLifetimeValue / rawRecords.length : 0;

      return this.success(
        {
          record_count: rawRecords.length,
          tier_analysis: tierAnalysis,
          value_segments: valueSegments,
          total_lifetime_value: Math.round(totalLifetimeValue * 100) / 100,
          avg_customer_value: Math.round(avgCustomerValue * 100) / 100,
          transformation_type: 'customer_analytics',
          source: 'extract_customer_data',
          region_distribution: extractResults.region_breakdown,
          transformed_at: new Date().toISOString(),
        },
        { transform_time_ms: Math.random() * 250 + 40 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 7: AggregateData (depends on all 3 transforms)
// ---------------------------------------------------------------------------

export class AggregateDataHandler extends StepHandler {
  static handlerName = 'DataPipeline.StepHandlers.AggregateMetricsHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const salesData = context.getDependencyResult('transform_sales') as Record<string, unknown>;
      const inventoryData = context.getDependencyResult('transform_inventory') as Record<string, unknown>;
      const customerData = context.getDependencyResult('transform_customers') as Record<string, unknown>;

      // Validate all sources present
      const missing: string[] = [];
      if (!salesData) missing.push('transform_sales');
      if (!inventoryData) missing.push('transform_inventory');
      if (!customerData) missing.push('transform_customers');

      if (missing.length > 0) {
        return this.failure(
          `Missing transform results: ${missing.join(', ')}`,
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      // Extract metrics from each source (matching source key names)
      const totalRevenue = (salesData?.total_revenue as number) || 0;
      const salesRecordCount = (salesData?.record_count as number) || 0;

      const totalInventory = (inventoryData?.total_quantity_on_hand as number) || 0;
      const reorderAlerts = (inventoryData?.reorder_alerts as number) || 0;

      const totalCustomers = (customerData?.record_count as number) || 0;
      const totalLtv = (customerData?.total_lifetime_value as number) || 0;

      // Calculate cross-source metrics
      const revenuePerCustomer = totalCustomers > 0 ? totalRevenue / totalCustomers : 0;
      const inventoryTurnover = totalInventory > 0 ? totalRevenue / totalInventory : 0;

      return this.success(
        {
          total_revenue: totalRevenue,
          total_inventory_quantity: totalInventory,
          total_customers: totalCustomers,
          total_customer_lifetime_value: totalLtv,
          sales_transactions: salesRecordCount,
          inventory_reorder_alerts: reorderAlerts,
          revenue_per_customer: Math.round(revenuePerCustomer * 100) / 100,
          inventory_turnover_indicator: Math.round(inventoryTurnover * 10000) / 10000,
          aggregation_complete: true,
          sources_included: 3,
          aggregated_at: new Date().toISOString(),
        },
        { aggregation_time_ms: Math.random() * 150 + 30 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 8: GenerateInsights (depends on AggregateData)
// ---------------------------------------------------------------------------

export class GenerateInsightsHandler extends StepHandler {
  static handlerName = 'DataPipeline.StepHandlers.GenerateInsightsHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const metrics = context.getDependencyResult('aggregate_metrics') as Record<string, unknown>;

      if (!metrics) {
        return this.failure('Aggregated metrics not found', ErrorType.PERMANENT_ERROR, false);
      }

      const insights: Array<{ category: string; finding: string; metric: number; recommendation: string }> = [];

      // Revenue insights (matching source key reads)
      const revenue = (metrics.total_revenue as number) || 0;
      const customers = (metrics.total_customers as number) || 0;
      const revenuePerCustomer = (metrics.revenue_per_customer as number) || 0;

      if (revenue > 0) {
        insights.push({
          category: 'Revenue',
          finding: `Total revenue of $${revenue} with ${customers} customers`,
          metric: revenuePerCustomer,
          recommendation:
            revenuePerCustomer < 500 ? 'Consider upselling strategies' : 'Customer spend is healthy',
        });
      }

      // Inventory insights
      const inventoryAlerts = (metrics.inventory_reorder_alerts as number) || 0;
      if (inventoryAlerts > 0) {
        insights.push({
          category: 'Inventory',
          finding: `${inventoryAlerts} products need reordering`,
          metric: inventoryAlerts,
          recommendation: 'Review reorder points and place purchase orders',
        });
      } else {
        insights.push({
          category: 'Inventory',
          finding: 'All products above reorder points',
          metric: 0,
          recommendation: 'Inventory levels are healthy',
        });
      }

      // Customer insights
      const totalLtv = (metrics.total_customer_lifetime_value as number) || 0;
      const avgLtv = customers > 0 ? totalLtv / customers : 0;

      insights.push({
        category: 'Customer Value',
        finding: `Average customer lifetime value: $${avgLtv.toFixed(2)}`,
        metric: avgLtv,
        recommendation:
          avgLtv > 3000 ? 'Focus on retention programs' : 'Increase customer engagement',
      });

      // Business health score
      let score = 0;
      if (revenuePerCustomer > 500) score += 40;
      if (inventoryAlerts === 0) score += 30;
      if (avgLtv > 3000) score += 30;

      let rating: string;
      if (score >= 80) rating = 'Excellent';
      else if (score >= 60) rating = 'Good';
      else if (score >= 40) rating = 'Fair';
      else rating = 'Needs Improvement';

      const healthScore = { score, max_score: 100, rating };

      return this.success(
        {
          insights,
          health_score: healthScore,
          total_metrics_analyzed: Object.keys(metrics).length,
          pipeline_complete: true,
          generated_at: new Date().toISOString(),
        },
        { insight_generation_ms: Math.random() * 500 + 100 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}
