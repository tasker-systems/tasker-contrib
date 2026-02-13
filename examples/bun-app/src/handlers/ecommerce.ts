import {
  StepHandler,
  type StepContext,
  type StepHandlerResult,
  ErrorType,
} from '@tasker-systems/tasker';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface CartItem {
  sku: string;
  name: string;
  price: number;
  quantity: number;
}

interface PaymentInfo {
  method: string;
  card_last_four?: string;
  token?: string;
}

// ---------------------------------------------------------------------------
// Step 1: ValidateCart
// ---------------------------------------------------------------------------

export class ValidateCartHandler extends StepHandler {
  static handlerName = 'Ecommerce.StepHandlers.ValidateCartHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const cartItems = context.getInput<CartItem[]>('cart_items');

      if (!cartItems || cartItems.length === 0) {
        return this.failure(
          'Cart is empty or missing',
          ErrorType.VALIDATION_ERROR,
          false,
        );
      }

      // Validate each item has required fields and positive values
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
        return this.failure(
          `All cart items invalid: ${errors.join('; ')}`,
          ErrorType.VALIDATION_ERROR,
          false,
        );
      }

      // Calculate pricing breakdown
      const subtotal = validatedItems.reduce(
        (sum, item) => sum + item.price * item.quantity,
        0,
      );
      const taxRate = 0.0875; // 8.75% tax
      const tax = Math.round(subtotal * taxRate * 100) / 100;
      const shippingThreshold = 75.0;
      const shipping = subtotal >= shippingThreshold ? 0 : 9.99;
      const total = Math.round((subtotal + tax + shipping) * 100) / 100;

      return this.success(
        {
          validated_items: validatedItems,
          item_count: validatedItems.length,
          subtotal,
          tax,
          tax_rate: taxRate,
          shipping,
          total,
          free_shipping: subtotal >= shippingThreshold,
          validation_warnings: errors,
        },
        { processing_time_ms: Math.random() * 50 + 10 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 2: ProcessPayment
// ---------------------------------------------------------------------------

export class ProcessPaymentHandler extends StepHandler {
  static handlerName = 'Ecommerce.StepHandlers.ProcessPaymentHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const paymentInfo = context.getInput<PaymentInfo>('payment_info');
      const cartResult = context.getDependencyResult('validate_cart') as Record<string, unknown> | null;

      if (!cartResult) {
        return this.failure(
          'Missing cart validation result',
          ErrorType.HANDLER_ERROR,
          true,
        );
      }

      const total = cartResult.total as number;
      const method = paymentInfo?.method || 'credit_card';

      // Simulate payment gateway interaction
      const transactionId = crypto.randomUUID();
      const authCode = Math.random().toString(36).substring(2, 8).toUpperCase();
      const processingFee = Math.round(total * 0.029 * 100) / 100; // 2.9% processing fee

      // Simulate occasional declined transactions for realism
      if (total > 10000) {
        return this.failure(
          'Transaction exceeds single-transaction limit of $10,000',
          ErrorType.VALIDATION_ERROR,
          false,
        );
      }

      return this.success(
        {
          transaction_id: transactionId,
          auth_code: authCode,
          amount_charged: total,
          processing_fee: processingFee,
          net_amount: Math.round((total - processingFee) * 100) / 100,
          payment_method: method,
          card_last_four: paymentInfo?.card_last_four || '4242',
          status: 'authorized',
          gateway: 'stripe_simulator',
          authorized_at: new Date().toISOString(),
        },
        { gateway_response_ms: Math.random() * 200 + 100 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.RETRYABLE_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 3: UpdateInventory
// ---------------------------------------------------------------------------

export class UpdateInventoryHandler extends StepHandler {
  static handlerName = 'Ecommerce.StepHandlers.UpdateInventoryHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const cartResult = context.getDependencyResult('validate_cart') as Record<string, unknown> | null;

      if (!cartResult) {
        return this.failure(
          'Missing cart validation result',
          ErrorType.HANDLER_ERROR,
          true,
        );
      }

      const items = cartResult.validated_items as CartItem[];
      const inventoryUpdates: Array<{
        sku: string;
        quantity_reserved: number;
        warehouse: string;
        reservation_id: string;
      }> = [];

      // Simulate inventory reservation per item
      for (const item of items) {
        const warehouse = item.quantity > 5 ? 'warehouse-east' : 'warehouse-west';
        inventoryUpdates.push({
          sku: item.sku,
          quantity_reserved: item.quantity,
          warehouse,
          reservation_id: crypto.randomUUID(),
        });
      }

      const totalUnitsReserved = inventoryUpdates.reduce(
        (sum, update) => sum + update.quantity_reserved,
        0,
      );

      return this.success(
        {
          inventory_updates: inventoryUpdates,
          total_units_reserved: totalUnitsReserved,
          reservation_expires_at: new Date(Date.now() + 30 * 60 * 1000).toISOString(), // 30 min hold
          all_items_available: true,
        },
        { inventory_lookup_ms: Math.random() * 80 + 20 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.RETRYABLE_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 4: CreateOrder
// ---------------------------------------------------------------------------

export class CreateOrderHandler extends StepHandler {
  static handlerName = 'Ecommerce.StepHandlers.CreateOrderHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const customerEmail = context.getInput<string>('customer_email');
      const cartResult = context.getDependencyResult('validate_cart') as Record<string, unknown>;
      const paymentResult = context.getDependencyResult('process_payment') as Record<string, unknown>;
      const inventoryResult = context.getDependencyResult('update_inventory') as Record<string, unknown>;

      if (!cartResult || !paymentResult || !inventoryResult) {
        return this.failure(
          'Missing required dependency results',
          ErrorType.HANDLER_ERROR,
          true,
        );
      }

      // Build the order record
      const orderNumber = `ORD-${Date.now()}-${Math.random().toString(36).substring(2, 6).toUpperCase()}`;
      const estimatedDeliveryDays = (cartResult.free_shipping as boolean) ? 5 : 3;
      const estimatedDelivery = new Date(
        Date.now() + estimatedDeliveryDays * 24 * 60 * 60 * 1000,
      ).toISOString();

      return this.success(
        {
          order_number: orderNumber,
          customer_email: customerEmail,
          items: cartResult.validated_items,
          subtotal: cartResult.subtotal,
          tax: cartResult.tax,
          shipping: cartResult.shipping,
          total: cartResult.total,
          transaction_id: paymentResult.transaction_id,
          inventory_reservations: (inventoryResult.inventory_updates as unknown[]).length,
          status: 'confirmed',
          estimated_delivery: estimatedDelivery,
          created_at: new Date().toISOString(),
        },
        { order_creation_ms: Math.random() * 30 + 10 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 5: SendConfirmation
// ---------------------------------------------------------------------------

export class SendConfirmationHandler extends StepHandler {
  static handlerName = 'Ecommerce.StepHandlers.SendConfirmationHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const orderResult = context.getDependencyResult('create_order') as Record<string, unknown>;

      if (!orderResult) {
        return this.failure(
          'Missing order creation result',
          ErrorType.HANDLER_ERROR,
          true,
        );
      }

      const customerEmail = orderResult.customer_email as string;
      const orderNumber = orderResult.order_number as string;
      const total = orderResult.total as number;
      const estimatedDelivery = orderResult.estimated_delivery as string;

      // Simulate sending confirmation email
      const messageId = crypto.randomUUID();
      const templateVersion = 'order_confirmation_v3';

      return this.success(
        {
          message_id: messageId,
          recipient: customerEmail,
          template: templateVersion,
          subject: `Order Confirmed: ${orderNumber}`,
          order_summary: {
            order_number: orderNumber,
            total: `$${total.toFixed(2)}`,
            estimated_delivery: estimatedDelivery,
            item_count: (orderResult.items as unknown[]).length,
          },
          delivery_status: 'queued',
          sent_at: new Date().toISOString(),
          provider: 'sendgrid_simulator',
        },
        { email_queue_ms: Math.random() * 100 + 50 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.RETRYABLE_ERROR,
        true,
      );
    }
  }
}
