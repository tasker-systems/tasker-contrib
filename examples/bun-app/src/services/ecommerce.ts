/**
 * E-commerce business logic.
 *
 * Pure functions that validate carts, process payments, manage inventory,
 * create orders, and send confirmations. No Tasker types — just plain
 * objects in, plain objects out.
 */

import { PermanentError } from '@tasker-systems/tasker';

import type {
  CartItem,
  PaymentInfo,
  EcommerceValidateCartResult,
  EcommerceProcessPaymentResult,
  EcommerceUpdateInventoryResult,
  EcommerceCreateOrderResult,
  EcommerceSendConfirmationResult,
} from './types';

export type { CartItem, PaymentInfo };

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const TAX_RATE = 0.0875;
const SHIPPING_THRESHOLD = 75.0;
const SHIPPING_COST = 9.99;

// ---------------------------------------------------------------------------
// Service functions
// ---------------------------------------------------------------------------

export function validateCartItems(cartItems: CartItem[] | undefined): EcommerceValidateCartResult {
  if (!cartItems || cartItems.length === 0) {
    throw new PermanentError('Cart is empty or missing');
  }

  const validatedItems: CartItem[] = [];
  const errors: string[] = [];

  for (const item of cartItems) {
    if (!item.sku || !item.name) {
      errors.push(`Item missing sku or name: ${JSON.stringify(item)}`);
      continue;
    }
    if (item.price <= 0) {
      errors.push(`Invalid price for ${item.sku}: ${item.price}`);
      continue;
    }
    if (!Number.isInteger(item.quantity) || item.quantity <= 0) {
      errors.push(`Invalid quantity for ${item.sku}: ${item.quantity}`);
      continue;
    }
    validatedItems.push(item);
  }

  if (errors.length > 0 && validatedItems.length === 0) {
    throw new PermanentError(`All cart items invalid: ${errors.join('; ')}`);
  }

  const subtotal = validatedItems.reduce(
    (sum, item) => sum + item.price * item.quantity,
    0,
  );
  const tax = Math.round(subtotal * TAX_RATE * 100) / 100;
  const shipping = subtotal >= SHIPPING_THRESHOLD ? 0 : SHIPPING_COST;
  const total = Math.round((subtotal + tax + shipping) * 100) / 100;

  return {
    validated_items: validatedItems,
    item_count: validatedItems.length,
    subtotal,
    tax,
    tax_rate: TAX_RATE,
    shipping,
    total,
    free_shipping: subtotal >= SHIPPING_THRESHOLD,
    validation_warnings: errors,
  };
}

export function processPayment(
  cartResult: Record<string, unknown>,
  paymentInfo: PaymentInfo | undefined,
): EcommerceProcessPaymentResult {
  const total = cartResult.total as number;
  const method = paymentInfo?.method || 'credit_card';

  if (total > 10000) {
    throw new PermanentError('Transaction exceeds single-transaction limit of $10,000');
  }

  const transactionId = crypto.randomUUID();
  const authCode = Math.random().toString(36).substring(2, 8).toUpperCase();
  const processingFee = Math.round(total * 0.029 * 100) / 100;

  return {
    payment_id: `pay_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
    transaction_id: transactionId,
    status: 'succeeded',
    amount_charged: total,
    currency: 'USD',
    payment_method: method,
    auth_code: authCode,
    processing_fee: processingFee,
    net_amount: Math.round((total - processingFee) * 100) / 100,
    card_last_four: paymentInfo?.card_last_four || '4242',
    gateway: 'stripe_simulator',
    authorized_at: new Date().toISOString(),
  };
}

export function updateInventory(
  items: CartItem[],
): EcommerceUpdateInventoryResult {
  const updatedProducts: Array<{
    sku: string;
    name: string;
    previous_stock: number;
    new_stock: number;
    quantity_reserved: number;
    reservation_id: string;
    warehouse: string;
  }> = [];

  let totalItemsReserved = 0;
  for (const item of items) {
    const warehouse = item.quantity > 5 ? 'warehouse-east' : 'warehouse-west';
    const previousStock = Math.floor(Math.random() * 100) + item.quantity;
    updatedProducts.push({
      sku: item.sku,
      name: item.name,
      previous_stock: previousStock,
      new_stock: previousStock - item.quantity,
      quantity_reserved: item.quantity,
      reservation_id: crypto.randomUUID(),
      warehouse,
    });
    totalItemsReserved += item.quantity;
  }

  return {
    updated_products: updatedProducts,
    total_items_reserved: totalItemsReserved,
    inventory_log_id: `log_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
    updated_at: new Date().toISOString(),
    reservation_expires_at: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
    all_items_available: true,
  };
}

export function createOrder(
  cartResult: Record<string, unknown>,
  paymentResult: Record<string, unknown>,
  inventoryResult: Record<string, unknown>,
  customerEmail: string | undefined,
): EcommerceCreateOrderResult {
  if (!customerEmail) {
    throw new PermanentError('Customer email is required but was not provided');
  }

  const orderId = Math.floor(Math.random() * 9000) + 1000;
  const orderNumber = `ORD-${Date.now()}-${Math.random().toString(36).substring(2, 6).toUpperCase()}`;
  const estimatedDeliveryDays = (cartResult.free_shipping as boolean) ? 5 : 3;
  const deliveryDate = new Date(
    Date.now() + estimatedDeliveryDays * 24 * 60 * 60 * 1000,
  );
  const estimatedDelivery = deliveryDate.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });

  return {
    order_id: orderId,
    order_number: orderNumber,
    status: 'confirmed',
    total_amount: cartResult.total,
    customer_email: customerEmail,
    created_at: new Date().toISOString(),
    estimated_delivery: estimatedDelivery,
    items: cartResult.validated_items,
    subtotal: cartResult.subtotal,
    tax: cartResult.tax,
    shipping: cartResult.shipping,
    transaction_id: paymentResult.transaction_id,
    inventory_reservations: (inventoryResult.updated_products as unknown[]).length,
  };
}

export function sendConfirmation(
  orderResult: Record<string, unknown>,
  cartResult: Record<string, unknown> | undefined,
  customerEmail: string | undefined,
): EcommerceSendConfirmationResult {
  if (!customerEmail) {
    throw new PermanentError('Customer email is required but was not provided');
  }

  const orderNumber = orderResult.order_number as string;
  const totalAmount = orderResult.total_amount as number;
  const estimatedDelivery = orderResult.estimated_delivery as string;
  const validatedItems = cartResult?.validated_items ?? [];

  const emailId = crypto.randomUUID();

  return {
    email_id: emailId,
    recipient: customerEmail,
    subject: `Order Confirmation - ${orderNumber}`,
    status: 'sent',
    sent_at: new Date().toISOString(),
    template: 'order_confirmation',
    template_data: {
      customer_name: customerEmail,
      order_number: orderNumber,
      total_amount: totalAmount,
      estimated_delivery: estimatedDelivery,
      items: validatedItems,
    },
    provider: 'sendgrid_simulator',
  };
}
