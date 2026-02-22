# frozen_string_literal: true

module DataPipeline
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    TransformSalesHandler = step_handler(
      'DataPipeline::StepHandlers::TransformSalesHandler',
      depends_on: { sales_data: ['extract_sales_data', Types::DataPipeline::ExtractSalesResult] }
    ) do |sales_data:, context:|
      DataPipeline::Service.transform_sales(sales_data: sales_data)
    end
  end
end
