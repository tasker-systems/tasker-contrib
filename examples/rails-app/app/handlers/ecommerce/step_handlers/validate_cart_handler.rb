# frozen_string_literal: true

module Ecommerce
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    ValidateCartHandler = step_handler(
      'Ecommerce::StepHandlers::ValidateCartHandler',
      inputs: Types::Ecommerce::OrderInput
    ) do |inputs:, context:|
      Ecommerce::Service.validate_cart_items(cart_items: inputs.cart_items, customer_email: inputs.customer_email)
    end
  end
end
