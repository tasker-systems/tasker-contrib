# frozen_string_literal: true

module DataPipeline
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    TransformCustomersHandler = step_handler(
      'DataPipeline::StepHandlers::TransformCustomersHandler',
      depends_on: { customer_data: ['extract_customer_data', Types::DataPipeline::ExtractCustomerResult] }
    ) do |customer_data:, context:|
      DataPipeline::Service.transform_customers(customer_data: customer_data)
    end
  end
end
