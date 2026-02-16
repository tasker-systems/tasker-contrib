import 'dotenv/config';
import { WorkerServer } from '@tasker-systems/tasker';
import { createApp } from './app';

// Import handlers so they register with the handler system
import { ValidateCartHandler, ProcessPaymentHandler, UpdateInventoryHandler, CreateOrderHandler, SendConfirmationHandler } from './handlers/ecommerce';
import { ExtractSalesDataHandler, ExtractInventoryDataHandler, ExtractCustomerDataHandler, TransformSalesHandler, TransformInventoryHandler, TransformCustomerHandler, AggregateDataHandler, GenerateInsightsHandler } from './handlers/data-pipeline';
import { CreateUserHandler, SetupBillingHandler, InitPreferencesHandler, SendWelcomeHandler, UpdateStatusHandler } from './handlers/microservices';
import { ValidateRefundRequestHandler, CheckRefundEligibilityHandler, CalculateRefundAmountHandler, NotifyCustomerSuccessHandler, UpdateCrmRecordHandler } from './handlers/customer-success';
import { ProcessRefundPaymentHandler, UpdateLedgerHandler, ReconcileAccountHandler, GenerateRefundReceiptHandler } from './handlers/payments';

const app = createApp();

// Bootstrap tasker worker at startup
const server = new WorkerServer();

try {
  await server.start({ namespace: 'default' });

  // Register all handlers with the handler system
  const handlerSystem = server.getHandlerSystem();

  // E-commerce handlers
  handlerSystem.register(ValidateCartHandler.handlerName, ValidateCartHandler);
  handlerSystem.register(ProcessPaymentHandler.handlerName, ProcessPaymentHandler);
  handlerSystem.register(UpdateInventoryHandler.handlerName, UpdateInventoryHandler);
  handlerSystem.register(CreateOrderHandler.handlerName, CreateOrderHandler);
  handlerSystem.register(SendConfirmationHandler.handlerName, SendConfirmationHandler);

  // Data pipeline handlers
  handlerSystem.register(ExtractSalesDataHandler.handlerName, ExtractSalesDataHandler);
  handlerSystem.register(ExtractInventoryDataHandler.handlerName, ExtractInventoryDataHandler);
  handlerSystem.register(ExtractCustomerDataHandler.handlerName, ExtractCustomerDataHandler);
  handlerSystem.register(TransformSalesHandler.handlerName, TransformSalesHandler);
  handlerSystem.register(TransformInventoryHandler.handlerName, TransformInventoryHandler);
  handlerSystem.register(TransformCustomerHandler.handlerName, TransformCustomerHandler);
  handlerSystem.register(AggregateDataHandler.handlerName, AggregateDataHandler);
  handlerSystem.register(GenerateInsightsHandler.handlerName, GenerateInsightsHandler);

  // Microservices handlers
  handlerSystem.register(CreateUserHandler.handlerName, CreateUserHandler);
  handlerSystem.register(SetupBillingHandler.handlerName, SetupBillingHandler);
  handlerSystem.register(InitPreferencesHandler.handlerName, InitPreferencesHandler);
  handlerSystem.register(SendWelcomeHandler.handlerName, SendWelcomeHandler);
  handlerSystem.register(UpdateStatusHandler.handlerName, UpdateStatusHandler);

  // Customer success handlers (namespace: customer_success)
  handlerSystem.register(ValidateRefundRequestHandler.handlerName, ValidateRefundRequestHandler);
  handlerSystem.register(CheckRefundEligibilityHandler.handlerName, CheckRefundEligibilityHandler);
  handlerSystem.register(CalculateRefundAmountHandler.handlerName, CalculateRefundAmountHandler);
  handlerSystem.register(NotifyCustomerSuccessHandler.handlerName, NotifyCustomerSuccessHandler);
  handlerSystem.register(UpdateCrmRecordHandler.handlerName, UpdateCrmRecordHandler);

  // Payments handlers (namespace: payments)
  handlerSystem.register(ProcessRefundPaymentHandler.handlerName, ProcessRefundPaymentHandler);
  handlerSystem.register(UpdateLedgerHandler.handlerName, UpdateLedgerHandler);
  handlerSystem.register(ReconcileAccountHandler.handlerName, ReconcileAccountHandler);
  handlerSystem.register(GenerateRefundReceiptHandler.handlerName, GenerateRefundReceiptHandler);

  console.log(`Tasker worker started. Registered ${handlerSystem.handlerCount()} handlers.`);
} catch (error) {
  console.error('Failed to bootstrap Tasker worker:', error);
  console.warn('App will start without Tasker integration. Ensure infrastructure is running.');
}

const port = parseInt(process.env.PORT || '3002', 10);
console.log(`Bun + Hono example app listening on http://localhost:${port}`);

export default {
  port,
  fetch: app.fetch,
};
