# frozen_string_literal: true

module Microservices
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    UpdateUserStatusHandler = step_handler(
      'Microservices::StepHandlers::UpdateUserStatusHandler',
      depends_on: {
        account_data: ['create_user_account', Types::Microservices::CreateUserResult],
        billing_data: ['setup_billing_profile', Types::Microservices::SetupBillingResult],
        preferences_data: ['initialize_preferences', Types::Microservices::InitPreferencesResult],
        welcome_data: ['send_welcome_sequence', Types::Microservices::SendWelcomeResult]
      }
    ) do |account_data:, billing_data:, preferences_data:, welcome_data:, context:|
      Microservices::Service.update_user_status(
        account_data: account_data,
        billing_data: billing_data,
        preferences_data: preferences_data,
        welcome_data: welcome_data
      )
    end
  end
end
