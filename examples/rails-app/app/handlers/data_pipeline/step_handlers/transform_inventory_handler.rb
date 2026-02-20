# frozen_string_literal: true

module DataPipeline
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    TransformInventoryHandler = step_handler(
      'DataPipeline::StepHandlers::TransformInventoryHandler',
      depends_on: { inventory_data: ['extract_inventory_data', Types::DataPipeline::ExtractInventoryResult] }
    ) do |inventory_data:, context:|
      DataPipeline::Service.transform_inventory(inventory_data: inventory_data)
    end
  end
end
