# frozen_string_literal: true

module Ecommerce
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    ProcessPaymentHandler = step_handler(
      'Ecommerce::StepHandlers::ProcessPaymentHandler',
      depends_on: { cart_total: ['validate_cart', Types::Ecommerce::ValidateCartResult] },
      inputs: Types::Ecommerce::OrderInput
    ) do |cart_total:, inputs:, context:|
      Ecommerce::Service.process_payment(
        payment_info: inputs.payment_info,
        total: cart_total&.total
      )
    end
  end
end
