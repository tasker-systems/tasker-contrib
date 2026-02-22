# frozen_string_literal: true

module Microservices
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    SendWelcomeSequenceHandler = step_handler(
      'Microservices::StepHandlers::SendWelcomeSequenceHandler',
      depends_on: {
        account_data: ['create_user_account', Types::Microservices::CreateUserResult],
        billing_data: ['setup_billing_profile', Types::Microservices::SetupBillingResult],
        preferences_data: ['initialize_preferences', Types::Microservices::InitPreferencesResult]
      }
    ) do |account_data:, billing_data:, preferences_data:, context:|
      Microservices::Service.send_welcome_sequence(
        account_data: account_data,
        billing_data: billing_data,
        preferences_data: preferences_data
      )
    end
  end
end
