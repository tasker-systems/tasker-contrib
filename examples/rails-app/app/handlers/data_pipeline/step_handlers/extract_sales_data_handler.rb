# frozen_string_literal: true

module DataPipeline
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    ExtractSalesDataHandler = step_handler(
      'DataPipeline::StepHandlers::ExtractSalesDataHandler',
      inputs: Types::DataPipeline::PipelineInput
    ) do |inputs:, context:|
      DataPipeline::Service.extract_sales_data(
        source: inputs.source,
        date_range_start: inputs.resolved_date_range_start,
        date_range_end: inputs.resolved_date_range_end,
        granularity: inputs.granularity
      )
    end
  end
end
