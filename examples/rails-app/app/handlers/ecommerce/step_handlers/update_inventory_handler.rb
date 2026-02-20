# frozen_string_literal: true

module Ecommerce
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    UpdateInventoryHandler = step_handler(
      'Ecommerce::StepHandlers::UpdateInventoryHandler',
      depends_on: { cart_validation: ['validate_cart', Types::Ecommerce::ValidateCartResult] },
      inputs: Types::Ecommerce::OrderInput
    ) do |cart_validation:, inputs:, context:|
      Ecommerce::Service.update_inventory(
        cart_validation: cart_validation,
        customer_info: inputs.customer_info
      )
    end
  end
end
