# frozen_string_literal: true

module Ecommerce
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    SendConfirmationHandler = step_handler(
      'Ecommerce::StepHandlers::SendConfirmationHandler',
      depends_on: {
        order_result: ['create_order', Types::Ecommerce::CreateOrderResult],
        cart_validation: ['validate_cart', Types::Ecommerce::ValidateCartResult]
      },
      inputs: Types::Ecommerce::OrderInput
    ) do |order_result:, cart_validation:, inputs:, context:|
      Ecommerce::Service.send_confirmation(
        order_result: order_result,
        cart_validation: cart_validation,
        customer_email: inputs.customer_email
      )
    end
  end
end
