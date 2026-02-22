# frozen_string_literal: true

module DataPipeline
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    ExtractInventoryDataHandler = step_handler(
      'DataPipeline::StepHandlers::ExtractInventoryDataHandler',
      inputs: Types::DataPipeline::PipelineInput
    ) do |inputs:, context:|
      DataPipeline::Service.extract_inventory_data(
        source: inputs.source,
        filters: inputs.filters
      )
    end
  end
end
