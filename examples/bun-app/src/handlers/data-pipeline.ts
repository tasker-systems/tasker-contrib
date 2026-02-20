/**
 * Data pipeline step handlers.
 *
 * 8 steps demonstrating a fan-out / fan-in DAG:
 *   Extract (3 parallel) -> Transform (3 parallel) -> Aggregate -> GenerateInsights
 *
 * Thin DSL wrappers that delegate to ../services/data-pipeline for business logic.
 */

import { defineHandler } from '@tasker-systems/tasker';
import type { DateRange } from '../services/types';
import * as svc from '../services/data-pipeline';

// ---------------------------------------------------------------------------
// Step 1: ExtractSalesData (parallel with steps 2 and 3)
// ---------------------------------------------------------------------------

export const ExtractSalesDataHandler = defineHandler(
  'DataPipeline.StepHandlers.ExtractSalesDataHandler',
  { inputs: { sources: 'sources', dateRange: 'date_range' } },
  async ({ sources, dateRange }) =>
    svc.extractSalesData(
      sources as string[] | undefined,
      dateRange as DateRange | undefined,
    ),
);

// ---------------------------------------------------------------------------
// Step 2: ExtractInventoryData (parallel with steps 1 and 3)
// ---------------------------------------------------------------------------

export const ExtractInventoryDataHandler = defineHandler(
  'DataPipeline.StepHandlers.ExtractInventoryDataHandler',
  { inputs: { parameters: 'parameters' } },
  async ({ parameters }) =>
    svc.extractInventoryData(
      parameters as Record<string, unknown> | undefined,
    ),
);

// ---------------------------------------------------------------------------
// Step 3: ExtractCustomerData (parallel with steps 1 and 2)
// ---------------------------------------------------------------------------

export const ExtractCustomerDataHandler = defineHandler(
  'DataPipeline.StepHandlers.ExtractCustomerDataHandler',
  { inputs: { dateRange: 'date_range' } },
  async ({ dateRange }) =>
    svc.extractCustomerData(dateRange as DateRange | undefined),
);

// ---------------------------------------------------------------------------
// Step 4: TransformSales (depends on ExtractSalesData)
// ---------------------------------------------------------------------------

export const TransformSalesHandler = defineHandler(
  'DataPipeline.StepHandlers.TransformSalesHandler',
  { depends: { extractResults: 'extract_sales_data' } },
  async ({ extractResults }) =>
    svc.transformSales(extractResults as Record<string, unknown>),
);

// ---------------------------------------------------------------------------
// Step 5: TransformInventory (depends on ExtractInventoryData)
// ---------------------------------------------------------------------------

export const TransformInventoryHandler = defineHandler(
  'DataPipeline.StepHandlers.TransformInventoryHandler',
  { depends: { extractResults: 'extract_inventory_data' } },
  async ({ extractResults }) =>
    svc.transformInventory(extractResults as Record<string, unknown>),
);

// ---------------------------------------------------------------------------
// Step 6: TransformCustomer (depends on ExtractCustomerData)
// ---------------------------------------------------------------------------

export const TransformCustomerHandler = defineHandler(
  'DataPipeline.StepHandlers.TransformCustomersHandler',
  { depends: { extractResults: 'extract_customer_data' } },
  async ({ extractResults }) =>
    svc.transformCustomers(extractResults as Record<string, unknown>),
);

// ---------------------------------------------------------------------------
// Step 7: AggregateData (depends on all 3 transforms)
// ---------------------------------------------------------------------------

export const AggregateDataHandler = defineHandler(
  'DataPipeline.StepHandlers.AggregateMetricsHandler',
  {
    depends: {
      salesData: 'transform_sales',
      inventoryData: 'transform_inventory',
      customerData: 'transform_customers',
    },
  },
  async ({ salesData, inventoryData, customerData }) =>
    svc.aggregateMetrics(
      salesData as Record<string, unknown> | undefined,
      inventoryData as Record<string, unknown> | undefined,
      customerData as Record<string, unknown> | undefined,
    ),
);

// ---------------------------------------------------------------------------
// Step 8: GenerateInsights (depends on AggregateData)
// ---------------------------------------------------------------------------

export const GenerateInsightsHandler = defineHandler(
  'DataPipeline.StepHandlers.GenerateInsightsHandler',
  { depends: { metrics: 'aggregate_metrics' } },
  async ({ metrics }) =>
    svc.generateInsights(metrics as Record<string, unknown>),
);
