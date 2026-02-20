# frozen_string_literal: true

module Microservices
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    InitializePreferencesHandler = step_handler(
      'Microservices::StepHandlers::InitializePreferencesHandler',
      depends_on: { account_data: ['create_user_account', Types::Microservices::CreateUserResult] },
      inputs: Types::Microservices::CreateUserAccountInput
    ) do |account_data:, inputs:, context:|
      Microservices::Service.initialize_preferences(
        account_data: account_data,
        marketing_consent: inputs.marketing_consent
      )
    end
  end
end
