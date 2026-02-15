import { describe, test, expect, beforeAll } from 'bun:test';
import { resolve } from 'path';
import { createApp } from '../src/app';

// Workaround for TAS-282: bundled library path resolution bug in published package.
// The findBundledNativeLibrary() function miscalculates the package root when code
// is bundled into dist/index.js. Set the env var to the correct path.
if (!process.env.TASKER_FFI_LIBRARY_PATH) {
  const BUNDLED_LIBRARIES: Record<string, string> = {
    'linux-x64': 'libtasker_ts-linux-x64.so',
    'linux-arm64': 'libtasker_ts-linux-arm64.so',
    'darwin-arm64': 'libtasker_ts-darwin-arm64.dylib',
  };
  const filename = BUNDLED_LIBRARIES[`${process.platform}-${process.arch}`];
  if (filename) {
    process.env.TASKER_FFI_LIBRARY_PATH = resolve(
      import.meta.dir,
      '..',
      'node_modules',
      '@tasker-systems',
      'tasker',
      'native',
      filename,
    );
  }
}

// Create in-process Hono app — no external server needed.
const app = createApp();

/** Send a request to the in-process app. */
function req(path: string, init?: RequestInit) {
  return app.request(path, init);
}

/** POST JSON to the in-process app. */
function postJson(path: string, body: unknown) {
  return req(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('Health check', () => {
  test('returns ok status', async () => {
    const res = await req('/health');
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.status).toBe('ok');
    expect(body.timestamp).toBeDefined();
  });
});

describe('E-commerce workflow', () => {
  let orderId: number;
  let taskUuid: string | null;

  test('POST /orders creates order and initiates workflow', async () => {
    const res = await postJson('/orders', {
      customer_email: 'test@example.com',
      items: [
        { sku: 'WIDGET-001', name: 'Widget', price: 29.99, quantity: 2 },
        { sku: 'GADGET-002', name: 'Gadget', price: 49.99, quantity: 1 },
      ],
      payment_info: {
        method: 'credit_card',
        card_last_four: '4242',
      },
    });

    expect(res.status).toBe(201);

    const body = await res.json();
    expect(body.id).toBeDefined();
    expect(body.customer_email).toBe('test@example.com');
    expect(body.items).toHaveLength(2);
    expect(parseFloat(body.total)).toBeGreaterThan(0);
    expect(body.created_at).toBeDefined();

    orderId = body.id;
    taskUuid = body.task_uuid;
  });

  test('GET /orders/:id returns order with task status', async () => {
    const res = await req(`/orders/${orderId}`);
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.id).toBe(orderId);
    expect(body.customer_email).toBe('test@example.com');
    expect(body.items).toBeDefined();
    expect(body.total).toBeDefined();
    expect(body.created_at).toBeDefined();
    expect(body.updated_at).toBeDefined();

    if (taskUuid) {
      expect(body.task_uuid).toBe(taskUuid);
    }
  });

  test('POST /orders validates required fields', async () => {
    const res = await postJson('/orders', {
      customer_email: 'test@example.com',
      // Missing items
    });

    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBeDefined();
  });

  test('GET /orders/:id returns 404 for non-existent order', async () => {
    const res = await req('/orders/999999');
    expect(res.status).toBe(404);
  });
});

describe('Analytics pipeline workflow', () => {
  let jobId: number;

  test('POST /analytics/jobs creates job and initiates pipeline', async () => {
    const res = await postJson('/analytics/jobs', {
      job_name: 'Monthly Revenue Analysis',
      sources: ['sales_db', 'inventory_api', 'crm_export'],
      parameters: {
        date_start: '2024-01-01',
        date_end: '2024-01-31',
        include_archived: false,
      },
    });

    expect(res.status).toBe(201);

    const body = await res.json();
    expect(body.id).toBeDefined();
    expect(body.job_name).toBe('Monthly Revenue Analysis');
    expect(body.sources).toHaveLength(3);
    expect(body.created_at).toBeDefined();

    jobId = body.id;
  });

  test('GET /analytics/jobs/:id returns job with task status', async () => {
    const res = await req(`/analytics/jobs/${jobId}`);
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.id).toBe(jobId);
    expect(body.job_name).toBe('Monthly Revenue Analysis');
    expect(body.sources).toBeDefined();
    expect(body.parameters).toBeDefined();
  });

  test('POST /analytics/jobs validates required fields', async () => {
    const res = await postJson('/analytics/jobs', {
      job_name: 'Missing sources',
      // Missing sources
    });

    expect(res.status).toBe(400);
  });
});

describe('Microservices user registration workflow', () => {
  let requestId: number;

  test('POST /services/requests creates registration and initiates workflow', async () => {
    const res = await postJson('/services/requests', {
      username: 'testuser',
      email: 'testuser@example.com',
      plan: 'standard',
      metadata: {
        timezone: 'America/New_York',
        locale: 'en-US',
        referral_source: 'blog',
      },
    });

    expect(res.status).toBe(201);

    const body = await res.json();
    expect(body.id).toBeDefined();
    expect(body.username).toBe('testuser');
    expect(body.email).toBe('testuser@example.com');
    expect(body.plan).toBe('standard');
    expect(body.created_at).toBeDefined();

    requestId = body.id;
  });

  test('GET /services/requests/:id returns request with task status', async () => {
    const res = await req(`/services/requests/${requestId}`);
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.id).toBe(requestId);
    expect(body.username).toBe('testuser');
    expect(body.email).toBe('testuser@example.com');
  });

  test('POST /services/requests validates required fields', async () => {
    const res = await postJson('/services/requests', {
      username: 'onlyusername',
      // Missing email
    });

    expect(res.status).toBe(400);
  });
});

const completionDescribe = process.env.RUN_COMPLETION_TESTS ? describe : describe.skip;

completionDescribe('Task Completion Verification', () => {
  // Bootstrap the Tasker worker before completion tests.
  // This initializes WORKER_SYSTEM (required for TaskerClient.createTask()),
  // registers templates with orchestration, and starts step dispatch.
  beforeAll(async () => {
    const { WorkerServer } = await import('@tasker-systems/tasker');

    const server = new WorkerServer();
    await server.start({ namespace: 'default' });

    const handlerSystem = server.getHandlerSystem();

    // E-commerce handlers
    const ecommerce = await import('../src/handlers/ecommerce');
    handlerSystem.register(ecommerce.ValidateCartHandler.handlerName, ecommerce.ValidateCartHandler);
    handlerSystem.register(ecommerce.ProcessPaymentHandler.handlerName, ecommerce.ProcessPaymentHandler);
    handlerSystem.register(ecommerce.UpdateInventoryHandler.handlerName, ecommerce.UpdateInventoryHandler);
    handlerSystem.register(ecommerce.CreateOrderHandler.handlerName, ecommerce.CreateOrderHandler);
    handlerSystem.register(ecommerce.SendConfirmationHandler.handlerName, ecommerce.SendConfirmationHandler);

    // Data pipeline handlers
    const dataPipeline = await import('../src/handlers/data-pipeline');
    handlerSystem.register(dataPipeline.ExtractSalesDataHandler.handlerName, dataPipeline.ExtractSalesDataHandler);
    handlerSystem.register(dataPipeline.ExtractInventoryDataHandler.handlerName, dataPipeline.ExtractInventoryDataHandler);
    handlerSystem.register(dataPipeline.ExtractCustomerDataHandler.handlerName, dataPipeline.ExtractCustomerDataHandler);
    handlerSystem.register(dataPipeline.TransformSalesHandler.handlerName, dataPipeline.TransformSalesHandler);
    handlerSystem.register(dataPipeline.TransformInventoryHandler.handlerName, dataPipeline.TransformInventoryHandler);
    handlerSystem.register(dataPipeline.TransformCustomerHandler.handlerName, dataPipeline.TransformCustomerHandler);
    handlerSystem.register(dataPipeline.AggregateDataHandler.handlerName, dataPipeline.AggregateDataHandler);
    handlerSystem.register(dataPipeline.GenerateInsightsHandler.handlerName, dataPipeline.GenerateInsightsHandler);

    // Microservices handlers
    const microservices = await import('../src/handlers/microservices');
    handlerSystem.register(microservices.CreateUserHandler.handlerName, microservices.CreateUserHandler);
    handlerSystem.register(microservices.SetupBillingHandler.handlerName, microservices.SetupBillingHandler);
    handlerSystem.register(microservices.InitPreferencesHandler.handlerName, microservices.InitPreferencesHandler);
    handlerSystem.register(microservices.SendWelcomeHandler.handlerName, microservices.SendWelcomeHandler);
    handlerSystem.register(microservices.UpdateStatusHandler.handlerName, microservices.UpdateStatusHandler);

    // Customer success handlers
    const customerSuccess = await import('../src/handlers/customer-success');
    handlerSystem.register(customerSuccess.ValidateRefundRequestHandler.handlerName, customerSuccess.ValidateRefundRequestHandler);
    handlerSystem.register(customerSuccess.CheckRefundEligibilityHandler.handlerName, customerSuccess.CheckRefundEligibilityHandler);
    handlerSystem.register(customerSuccess.CalculateRefundAmountHandler.handlerName, customerSuccess.CalculateRefundAmountHandler);
    handlerSystem.register(customerSuccess.NotifyCustomerSuccessHandler.handlerName, customerSuccess.NotifyCustomerSuccessHandler);
    handlerSystem.register(customerSuccess.UpdateCrmRecordHandler.handlerName, customerSuccess.UpdateCrmRecordHandler);

    // Payments handlers
    const payments = await import('../src/handlers/payments');
    handlerSystem.register(payments.ProcessRefundPaymentHandler.handlerName, payments.ProcessRefundPaymentHandler);
    handlerSystem.register(payments.UpdateLedgerHandler.handlerName, payments.UpdateLedgerHandler);
    handlerSystem.register(payments.ReconcileAccountHandler.handlerName, payments.ReconcileAccountHandler);
    handlerSystem.register(payments.GenerateRefundReceiptHandler.handlerName, payments.GenerateRefundReceiptHandler);

    console.log(`Tasker worker bootstrapped with ${handlerSystem.handlerCount()} handlers`);
  }, 30_000); // 30s timeout for worker bootstrap

  // NOTE: Completion tests create tasks directly via the orchestration REST API
  // rather than through app routes. This is because TAS-283 (koffi FFI JSON
  // "trailing input" bug) prevents the TaskerClient.createTask() FFI calls from
  // working in the published @tasker-systems/tasker package. Once TAS-283 is
  // fixed, these tests should be updated to go through the app routes for full
  // end-to-end verification.

  const ORCHESTRATION_URL = process.env.ORCHESTRATION_URL || 'http://localhost:8080';
  const API_KEY = process.env.TASKER_API_KEY || 'test-api-key-full-access';

  /** Unique suffix per test run to avoid idempotency conflicts. */
  const runId = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);

  /** Create a task directly via the orchestration REST API. */
  async function createTaskViaApi(payload: Record<string, unknown>): Promise<string> {
    const res = await fetch(`${ORCHESTRATION_URL}/v1/tasks`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': API_KEY,
      },
      body: JSON.stringify(payload),
    });

    if (!res.ok) {
      throw new Error(`POST /v1/tasks returned ${res.status}: ${await res.text()}`);
    }

    const body = await res.json() as { task_uuid: string };
    return body.task_uuid;
  }

  test('E-commerce order dispatches steps and reaches terminal status', async () => {
    const { waitForTaskCompletion } = await import('./helpers');

    const taskUuid = await createTaskViaApi({
      name: 'ecommerce_order_processing',
      namespace: 'ecommerce_ts',
      version: '1.0.0',
      initiator: 'bun-completion-test',
      source_system: 'example-bun-app',
      reason: `Completion test - e-commerce order (${runId})`,
      context: {
        order_id: 99901,
        test_run_id: runId,
        customer_email: 'completion-test@example.com',
        cart_items: [{ sku: 'COMPLETION-001', name: 'Completion Widget', price: 19.99, quantity: 1 }],
        payment_info: { method: 'credit_card', card_last_four: '4242' },
      },
    });

    const task = await waitForTaskCompletion(taskUuid);

    // Task reached a terminal status (infrastructure loop works)
    expect(['complete', 'blocked_by_failures', 'error']).toContain(task.status);
    expect(task.total_steps).toBe(5);

    // At least the first step was attempted (handler dispatch works)
    expect(task.steps).toHaveLength(5);
    const validateStep = task.steps.find((s) => s.name === 'validate_cart');
    expect(validateStep).toBeDefined();
    expect(validateStep!.attempts).toBeGreaterThanOrEqual(1);

    const completed = task.steps.filter((s) => s.current_state === 'complete').length;
    console.log(`  E-commerce task: ${task.status} (${completed}/5 steps complete)`);
  });

  test('User registration dispatches diamond pattern and reaches terminal status', async () => {
    const { waitForTaskCompletion } = await import('./helpers');

    const taskUuid = await createTaskViaApi({
      name: 'user_registration',
      namespace: 'microservices_ts',
      version: '1.0.0',
      initiator: 'bun-completion-test',
      source_system: 'example-bun-app',
      reason: `Completion test - user registration (${runId})`,
      context: {
        test_run_id: runId,
        username: 'completion-test-user',
        email: 'completion-test@example.com',
        plan: 'standard',
        metadata: { timezone: 'UTC', locale: 'en-US' },
      },
    });

    const task = await waitForTaskCompletion(taskUuid);

    // Task reached a terminal status (infrastructure loop works)
    expect(['complete', 'blocked_by_failures', 'error']).toContain(task.status);
    expect(task.total_steps).toBe(5);

    // Verify diamond pattern steps are present
    expect(task.steps).toHaveLength(5);
    const stepNames = task.steps.map((s) => s.name);
    expect(stepNames).toContain('create_user_account');
    expect(stepNames).toContain('setup_billing_profile');
    expect(stepNames).toContain('initialize_preferences');
    expect(stepNames).toContain('send_welcome_sequence');
    expect(stepNames).toContain('update_user_status');

    // At least the first step was attempted (handler dispatch works)
    const createStep = task.steps.find((s) => s.name === 'create_user_account');
    expect(createStep).toBeDefined();
    expect(createStep!.attempts).toBeGreaterThanOrEqual(1);

    const completed = task.steps.filter((s) => s.current_state === 'complete').length;
    console.log(`  User registration task: ${task.status} (${completed}/5 steps complete)`);
  });

  test('Customer success refund dispatches steps and reaches terminal status', async () => {
    const { waitForTaskCompletion } = await import('./helpers');

    const taskUuid = await createTaskViaApi({
      name: 'process_refund',
      namespace: 'customer_success_ts',
      version: '1.0.0',
      initiator: 'bun-completion-test',
      source_system: 'example-bun-app',
      reason: `Completion test - customer success refund (${runId})`,
      context: {
        test_run_id: runId,
        ticket_id: 'TKT-COMPLETION-001',
        customer_id: 'CUST-COMPLETION-001',
        customer_email: 'cs-completion@example.com',
        refund_amount: 49.99,
        refund_reason: 'defective_product',
      },
    });

    const task = await waitForTaskCompletion(taskUuid);

    // Task reached a terminal status
    expect(['complete', 'blocked_by_failures', 'error']).toContain(task.status);
    expect(task.total_steps).toBe(5);

    // Verify all customer success steps are present
    expect(task.steps).toHaveLength(5);
    const stepNames = task.steps.map((s) => s.name);
    expect(stepNames).toContain('validate_refund_request');
    expect(stepNames).toContain('check_refund_policy');
    expect(stepNames).toContain('get_manager_approval');
    expect(stepNames).toContain('execute_refund_workflow');
    expect(stepNames).toContain('update_ticket_status');

    // At least the first step was attempted
    const validateStep = task.steps.find((s) => s.name === 'validate_refund_request');
    expect(validateStep).toBeDefined();
    expect(validateStep!.attempts).toBeGreaterThanOrEqual(1);

    const completed = task.steps.filter((s) => s.current_state === 'complete').length;
    console.log(`  Customer success refund task: ${task.status} (${completed}/5 steps complete)`);
  });

  test('Payments refund dispatches steps and reaches terminal status', async () => {
    const { waitForTaskCompletion } = await import('./helpers');

    const taskUuid = await createTaskViaApi({
      name: 'process_refund',
      namespace: 'payments_ts',
      version: '1.0.0',
      initiator: 'bun-completion-test',
      source_system: 'example-bun-app',
      reason: `Completion test - payments refund (${runId})`,
      context: {
        test_run_id: runId,
        payment_id: 'pay_completion01',
        customer_email: 'pay-completion@example.com',
        refund_amount: 29.99,
        reason: 'customer_request',
      },
    });

    const task = await waitForTaskCompletion(taskUuid);

    // Task reached a terminal status
    expect(['complete', 'blocked_by_failures', 'error']).toContain(task.status);
    expect(task.total_steps).toBe(4);

    // Verify all payments steps are present
    expect(task.steps).toHaveLength(4);
    const stepNames = task.steps.map((s) => s.name);
    expect(stepNames).toContain('validate_payment_eligibility');
    expect(stepNames).toContain('process_gateway_refund');
    expect(stepNames).toContain('update_payment_records');
    expect(stepNames).toContain('notify_customer');

    // At least the first step was attempted
    const validateStep = task.steps.find((s) => s.name === 'validate_payment_eligibility');
    expect(validateStep).toBeDefined();
    expect(validateStep!.attempts).toBeGreaterThanOrEqual(1);

    const completed = task.steps.filter((s) => s.current_state === 'complete').length;
    console.log(`  Payments refund task: ${task.status} (${completed}/4 steps complete)`);
  });

  test('Analytics pipeline dispatches parallel branches and reaches terminal status', async () => {
    const { waitForTaskCompletion } = await import('./helpers');

    const taskUuid = await createTaskViaApi({
      name: 'analytics_pipeline',
      namespace: 'data_pipeline_ts',
      version: '1.0.0',
      initiator: 'bun-completion-test',
      source_system: 'example-bun-app',
      reason: `Completion test - analytics pipeline (${runId})`,
      context: {
        test_run_id: runId,
        job_name: 'Completion Test Pipeline',
        sources: ['sales_db', 'inventory_api', 'crm_export'],
        parameters: { date_start: '2026-01-01', date_end: '2026-01-07' },
      },
    });

    const task = await waitForTaskCompletion(taskUuid);

    expect(['complete', 'blocked_by_failures', 'error']).toContain(task.status);
    expect(task.total_steps).toBe(8);

    const stepNames = task.steps.map((s) => s.name);
    expect(stepNames).toContain('extract_sales_data');
    expect(stepNames).toContain('extract_inventory_data');
    expect(stepNames).toContain('extract_customer_data');

    // At least one extract step was attempted (parallel dispatch works)
    const extractSteps = task.steps.filter((s) => s.name.startsWith('extract_'));
    const attempted = extractSteps.filter((s) => s.attempts > 0).length;
    expect(attempted).toBeGreaterThanOrEqual(1);

    const completed = task.steps.filter((s) => s.current_state === 'complete').length;
    console.log(`  Analytics task: ${task.status} (${completed}/8 steps complete)`);
  });
});

describe('Compliance / Team scaling workflow', () => {
  let checkId: number;

  test('POST /compliance/checks creates check and initiates cross-namespace workflows', async () => {
    const res = await postJson('/compliance/checks', {
      check_type: 'refund',
      entity_type: 'order',
      entity_id: 'ORD-12345',
      parameters: {
        customer_email: 'refund@example.com',
        order_id: 'ORD-12345',
        reason: 'defective_product',
        refund_amount: '149.99',
        payment_method: 'credit_card',
        transaction_id: 'txn_abc123',
      },
    });

    expect(res.status).toBe(201);

    const body = await res.json();
    expect(body.id).toBeDefined();
    expect(body.check_type).toBe('refund');
    expect(body.entity_type).toBe('order');
    expect(body.entity_id).toBe('ORD-12345');
    expect(body.parent_correlation_id).toBeDefined();
    expect(body.created_at).toBeDefined();

    // The response includes task UUIDs for both namespaces
    expect(body.task_uuids).toBeDefined();
    if (body.task_uuids) {
      expect(body.task_uuids).toHaveProperty('customer_success_ts');
      expect(body.task_uuids).toHaveProperty('payments_ts');
    }

    checkId = body.id;
  });

  test('GET /compliance/checks/:id returns check with task status', async () => {
    const res = await req(`/compliance/checks/${checkId}`);
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.id).toBe(checkId);
    expect(body.check_type).toBe('refund');
    expect(body.entity_type).toBe('order');
  });

  test('POST /compliance/checks validates required fields', async () => {
    const res = await postJson('/compliance/checks', {
      check_type: 'refund',
      // Missing entity_type and entity_id
    });

    expect(res.status).toBe(400);
  });
});
