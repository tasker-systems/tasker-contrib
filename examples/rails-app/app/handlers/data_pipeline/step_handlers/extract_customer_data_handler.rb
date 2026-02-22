# frozen_string_literal: true

module DataPipeline
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    ExtractCustomerDataHandler = step_handler(
      'DataPipeline::StepHandlers::ExtractCustomerDataHandler',
      inputs: Types::DataPipeline::PipelineInput
    ) do |inputs:, context:|
      DataPipeline::Service.extract_customer_data(
        source: inputs.source,
        date_range_start: inputs.resolved_date_range_start
      )
    end
  end
end
