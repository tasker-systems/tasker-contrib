import { describe, test, expect, beforeAll, afterAll } from 'bun:test';

const BASE_URL = process.env.TEST_BASE_URL || 'http://localhost:3002';

// Wait for the app to be ready before running tests
beforeAll(async () => {
  const maxRetries = 10;
  const retryDelay = 1000;

  for (let i = 0; i < maxRetries; i++) {
    try {
      const res = await fetch(`${BASE_URL}/health`);
      if (res.ok) {
        console.log('App is ready');
        return;
      }
    } catch {
      // App not ready yet
    }
    await new Promise((resolve) => setTimeout(resolve, retryDelay));
  }
  throw new Error('App did not become ready within timeout');
});

describe('Health check', () => {
  test('returns ok status', async () => {
    const res = await fetch(`${BASE_URL}/health`);
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
    const res = await fetch(`${BASE_URL}/orders`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        customer_email: 'test@example.com',
        items: [
          { sku: 'WIDGET-001', name: 'Widget', price: 29.99, quantity: 2 },
          { sku: 'GADGET-002', name: 'Gadget', price: 49.99, quantity: 1 },
        ],
        payment_info: {
          method: 'credit_card',
          card_last_four: '4242',
        },
      }),
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
    const res = await fetch(`${BASE_URL}/orders/${orderId}`);
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
    const res = await fetch(`${BASE_URL}/orders`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        customer_email: 'test@example.com',
        // Missing items
      }),
    });

    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBeDefined();
  });

  test('GET /orders/:id returns 404 for non-existent order', async () => {
    const res = await fetch(`${BASE_URL}/orders/999999`);
    expect(res.status).toBe(404);
  });
});

describe('Analytics pipeline workflow', () => {
  let jobId: number;

  test('POST /analytics/jobs creates job and initiates pipeline', async () => {
    const res = await fetch(`${BASE_URL}/analytics/jobs`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        job_name: 'Monthly Revenue Analysis',
        sources: ['sales_db', 'inventory_api', 'crm_export'],
        parameters: {
          date_start: '2024-01-01',
          date_end: '2024-01-31',
          include_archived: false,
        },
      }),
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
    const res = await fetch(`${BASE_URL}/analytics/jobs/${jobId}`);
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.id).toBe(jobId);
    expect(body.job_name).toBe('Monthly Revenue Analysis');
    expect(body.sources).toBeDefined();
    expect(body.parameters).toBeDefined();
  });

  test('POST /analytics/jobs validates required fields', async () => {
    const res = await fetch(`${BASE_URL}/analytics/jobs`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        job_name: 'Missing sources',
        // Missing sources
      }),
    });

    expect(res.status).toBe(400);
  });
});

describe('Microservices user registration workflow', () => {
  let requestId: number;

  test('POST /services/requests creates registration and initiates workflow', async () => {
    const res = await fetch(`${BASE_URL}/services/requests`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'testuser',
        email: 'testuser@example.com',
        plan: 'standard',
        metadata: {
          timezone: 'America/New_York',
          locale: 'en-US',
          referral_source: 'blog',
        },
      }),
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
    const res = await fetch(`${BASE_URL}/services/requests/${requestId}`);
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.id).toBe(requestId);
    expect(body.username).toBe('testuser');
    expect(body.email).toBe('testuser@example.com');
  });

  test('POST /services/requests validates required fields', async () => {
    const res = await fetch(`${BASE_URL}/services/requests`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'onlyusername',
        // Missing email
      }),
    });

    expect(res.status).toBe(400);
  });
});

describe('Compliance / Team scaling workflow', () => {
  let checkId: number;

  test('POST /compliance/checks creates check and initiates cross-namespace workflows', async () => {
    const res = await fetch(`${BASE_URL}/compliance/checks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
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
      }),
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
      expect(body.task_uuids).toHaveProperty('customer_success');
      expect(body.task_uuids).toHaveProperty('payments');
    }

    checkId = body.id;
  });

  test('GET /compliance/checks/:id returns check with task status', async () => {
    const res = await fetch(`${BASE_URL}/compliance/checks/${checkId}`);
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.id).toBe(checkId);
    expect(body.check_type).toBe('refund');
    expect(body.entity_type).toBe('order');
  });

  test('POST /compliance/checks validates required fields', async () => {
    const res = await fetch(`${BASE_URL}/compliance/checks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        check_type: 'refund',
        // Missing entity_type and entity_id
      }),
    });

    expect(res.status).toBe(400);
  });
});
