# frozen_string_literal: true

module DataPipeline
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    GenerateInsightsHandler = step_handler(
      'DataPipeline::StepHandlers::GenerateInsightsHandler',
      depends_on: { aggregation: ['aggregate_metrics', Types::DataPipeline::AggregateMetricsResult] }
    ) do |aggregation:, context:|
      DataPipeline::Service.generate_insights(aggregation: aggregation)
    end
  end
end
