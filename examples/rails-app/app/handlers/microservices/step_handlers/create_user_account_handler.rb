# frozen_string_literal: true

module Microservices
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    CreateUserAccountHandler = step_handler(
      'Microservices::StepHandlers::CreateUserAccountHandler',
      inputs: Types::Microservices::CreateUserAccountInput
    ) do |inputs:, context:|
      # Input validation (required fields) is handled by the model's validate!
      # method — see Types::Microservices::CreateUserAccountInput in types.rb.
      Microservices::Service.create_user_account(input: inputs)
    end
  end
end
