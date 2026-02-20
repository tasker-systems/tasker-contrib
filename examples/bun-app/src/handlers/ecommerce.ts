/**
 * E-commerce order processing step handlers.
 *
 * 5 sequential steps demonstrating a linear pipeline:
 *   ValidateCart -> ProcessPayment -> UpdateInventory -> CreateOrder -> SendConfirmation
 *
 * Thin DSL wrappers that delegate to ../services/ecommerce for business logic.
 */

import { defineHandler } from '@tasker-systems/tasker';
import type { CartItem, PaymentInfo } from '../services/types';
import * as svc from '../services/ecommerce';

export const ValidateCartHandler = defineHandler(
  'Ecommerce.StepHandlers.ValidateCartHandler',
  { inputs: { cartItems: 'cart_items' } },
  async ({ cartItems }) => svc.validateCartItems(cartItems as CartItem[] | undefined),
);

export const ProcessPaymentHandler = defineHandler(
  'Ecommerce.StepHandlers.ProcessPaymentHandler',
  {
    depends: { cartResult: 'validate_cart' },
    inputs: { paymentInfo: 'payment_info' },
  },
  async ({ cartResult, paymentInfo }) =>
    svc.processPayment(
      cartResult as Record<string, unknown>,
      paymentInfo as PaymentInfo | undefined,
    ),
);

export const UpdateInventoryHandler = defineHandler(
  'Ecommerce.StepHandlers.UpdateInventoryHandler',
  { depends: { cartResult: 'validate_cart' } },
  async ({ cartResult }) =>
    svc.updateInventory(
      (cartResult as Record<string, unknown>).validated_items as CartItem[],
    ),
);

export const CreateOrderHandler = defineHandler(
  'Ecommerce.StepHandlers.CreateOrderHandler',
  {
    depends: {
      cartResult: 'validate_cart',
      paymentResult: 'process_payment',
      inventoryResult: 'update_inventory',
    },
    inputs: { customerEmail: 'customer_email' },
  },
  async ({ cartResult, paymentResult, inventoryResult, customerEmail }) =>
    svc.createOrder(
      cartResult as Record<string, unknown>,
      paymentResult as Record<string, unknown>,
      inventoryResult as Record<string, unknown>,
      customerEmail as string | undefined,
    ),
);

export const SendConfirmationHandler = defineHandler(
  'Ecommerce.StepHandlers.SendConfirmationHandler',
  {
    depends: {
      orderResult: 'create_order',
      cartResult: 'validate_cart',
    },
    inputs: { customerEmail: 'customer_email' },
  },
  async ({ orderResult, cartResult, customerEmail }) =>
    svc.sendConfirmation(
      orderResult as Record<string, unknown>,
      cartResult as Record<string, unknown> | undefined,
      customerEmail as string | undefined,
    ),
);
