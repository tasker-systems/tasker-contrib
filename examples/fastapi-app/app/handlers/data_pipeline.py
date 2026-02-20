"""Data pipeline analytics step handlers.

8 steps forming a DAG pattern with 3 parallel extract branches:
  extract_sales_data      ─┐
  extract_inventory_data  ─┤─> transform_sales     ─┐
  extract_customer_data   ─┘   transform_inventory  ─┤─> aggregate_metrics -> generate_insights
                                transform_customers  ─┘

Thin DSL wrappers that delegate to app.services.data_pipeline for business logic.
"""

from __future__ import annotations

from tasker_core.step_handler.functional import depends_on, inputs, step_handler
from tasker_core.types import StepContext

from app.services import data_pipeline as svc
from app.services.types import (
    DataPipelineInput,
    PipelineAggregateMetricsResult,
    PipelineExtractCustomerResult,
    PipelineExtractInventoryResult,
    PipelineExtractSalesResult,
    PipelineTransformCustomersResult,
    PipelineTransformInventoryResult,
    PipelineTransformSalesResult,
)


# ---------------------------------------------------------------------------
# Extract handlers
# ---------------------------------------------------------------------------


@step_handler("extract_sales_data")
@inputs(DataPipelineInput)
def extract_sales_data(inputs: DataPipelineInput, context: StepContext):
    return svc.extract_sales_data(
        source=inputs.source,
        date_range_start=inputs.date_range_start,
        date_range_end=inputs.date_range_end,
        granularity=inputs.granularity,
    )


@step_handler("extract_inventory_data")
@inputs(DataPipelineInput)
def extract_inventory_data(inputs: DataPipelineInput, context: StepContext):
    return svc.extract_inventory_data(
        source=inputs.source,
        date_range_start=inputs.date_range_start,
    )


@step_handler("extract_customer_data")
@inputs(DataPipelineInput)
def extract_customer_data(inputs: DataPipelineInput, context: StepContext):
    return svc.extract_customer_data(source=inputs.source)


# ---------------------------------------------------------------------------
# Transform handlers
# ---------------------------------------------------------------------------


@step_handler("transform_sales")
@depends_on(sales_data=("extract_sales_data", PipelineExtractSalesResult))
def transform_sales(sales_data: PipelineExtractSalesResult, context: StepContext):
    return svc.transform_sales(sales_data=sales_data)


@step_handler("transform_inventory")
@depends_on(traffic_data=("extract_inventory_data", PipelineExtractInventoryResult))
def transform_inventory(traffic_data: PipelineExtractInventoryResult, context: StepContext):
    return svc.transform_inventory(traffic_data=traffic_data)


@step_handler("transform_customers")
@depends_on(inventory_data=("extract_customer_data", PipelineExtractCustomerResult))
def transform_customers(inventory_data: PipelineExtractCustomerResult, context: StepContext):
    return svc.transform_customers(inventory_data=inventory_data)


# ---------------------------------------------------------------------------
# Aggregate and insight handlers
# ---------------------------------------------------------------------------


@step_handler("aggregate_metrics")
@depends_on(
    sales_transform=("transform_sales", PipelineTransformSalesResult),
    traffic_transform=("transform_inventory", PipelineTransformInventoryResult),
    inventory_transform=("transform_customers", PipelineTransformCustomersResult),
)
def aggregate_metrics(
    sales_transform: PipelineTransformSalesResult,
    traffic_transform: PipelineTransformInventoryResult,
    inventory_transform: PipelineTransformCustomersResult,
    context: StepContext,
):
    return svc.aggregate_metrics(
        sales_transform=sales_transform,
        traffic_transform=traffic_transform,
        inventory_transform=inventory_transform,
    )


@step_handler("generate_insights")
@depends_on(metrics=("aggregate_metrics", PipelineAggregateMetricsResult))
def generate_insights(metrics: PipelineAggregateMetricsResult, context: StepContext):
    return svc.generate_insights(metrics=metrics)
