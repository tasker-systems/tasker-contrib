# frozen_string_literal: true

module Ecommerce
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    CreateOrderHandler = step_handler(
      'Ecommerce::StepHandlers::CreateOrderHandler',
      depends_on: {
        cart_validation: ['validate_cart', Types::Ecommerce::ValidateCartResult],
        payment_result: ['process_payment', Types::Ecommerce::ProcessPaymentResult],
        inventory_result: ['update_inventory', Types::Ecommerce::UpdateInventoryResult]
      },
      inputs: Types::Ecommerce::OrderInput
    ) do |cart_validation:, payment_result:, inventory_result:, inputs:, context:|
      Ecommerce::Service.create_order(
        cart_validation: cart_validation,
        payment_result: payment_result,
        inventory_result: inventory_result,
        customer_email: inputs.customer_email,
        shipping_address: inputs.shipping_address
      )
    end
  end
end
