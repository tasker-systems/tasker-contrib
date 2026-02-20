# frozen_string_literal: true

module Microservices
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    SetupBillingProfileHandler = step_handler(
      'Microservices::StepHandlers::SetupBillingProfileHandler',
      depends_on: { account_data: ['create_user_account', Types::Microservices::CreateUserResult] }
    ) do |account_data:, context:|
      Microservices::Service.setup_billing_profile(account_data: account_data)
    end
  end
end
