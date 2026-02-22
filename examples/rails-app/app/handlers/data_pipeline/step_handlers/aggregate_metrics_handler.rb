# frozen_string_literal: true

module DataPipeline
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    AggregateMetricsHandler = step_handler(
      'DataPipeline::StepHandlers::AggregateMetricsHandler',
      depends_on: {
        sales_transform: ['transform_sales', Types::DataPipeline::TransformSalesResult],
        inventory_transform: ['transform_inventory', Types::DataPipeline::TransformInventoryResult],
        customer_transform: ['transform_customers', Types::DataPipeline::TransformCustomersResult]
      }
    ) do |sales_transform:, inventory_transform:, customer_transform:, context:|
      DataPipeline::Service.aggregate_metrics(
        sales_transform: sales_transform,
        inventory_transform: inventory_transform,
        customer_transform: customer_transform
      )
    end
  end
end
