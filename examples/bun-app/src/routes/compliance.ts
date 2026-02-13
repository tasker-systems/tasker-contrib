import { Hono } from 'hono';
import { eq } from 'drizzle-orm';
import { db } from '../db/client';
import { complianceChecks } from '../db/schema';
import { FfiLayer } from '@tasker-systems/tasker';
import type { ClientTaskRequest } from '@tasker-systems/tasker';

export const complianceRoute = new Hono();

/**
 * POST /compliance/checks
 *
 * Creates a new compliance check record, then creates two Tasker tasks
 * across different namespaces for the team scaling workflow pattern:
 * - customer_success namespace: 5 steps for refund validation and CRM
 * - payments namespace: 4 steps for payment processing and reconciliation
 */
complianceRoute.post('/', async (c) => {
  const body = await c.req.json();
  const { check_type, entity_type, entity_id, parameters } = body;

  if (!check_type || !entity_type || !entity_id) {
    return c.json({ error: 'check_type, entity_type, and entity_id are required' }, 400);
  }

  // Create domain record
  const [check] = await db
    .insert(complianceChecks)
    .values({
      checkType: check_type,
      entityType: entity_type,
      entityId: entity_id,
      parameters: parameters || {},
      status: 'pending',
    })
    .returning();

  // Create Tasker tasks for cross-namespace compliance workflow
  let customerSuccessTaskUuid: string | null = null;
  let paymentsTaskUuid: string | null = null;
  const parentCorrelationId = crypto.randomUUID();

  try {
    const ffiLayer = new FfiLayer();
    await ffiLayer.load();
    const runtime = ffiLayer.getRuntime();

    // Create customer success task (namespace: customer_success)
    const csTaskRequest: ClientTaskRequest = {
      name: 'customer_success_process_refund',
      namespace: 'customer_success',
      version: '1.0.0',
      context: {
        check_id: check.id,
        check_type,
        entity_type,
        entity_id,
        parameters: parameters || {},
        customer_email: parameters?.customer_email || 'customer@example.com',
        order_id: parameters?.order_id || entity_id,
        refund_reason: parameters?.reason || 'Customer request',
      },
      initiator: 'bun-app',
      source_system: 'example-bun-app',
      reason: `Customer success refund check for ${entity_type}:${entity_id}`,
      tags: ['compliance', 'customer-success', 'refund'],
      requested_at: new Date().toISOString(),
      options: null,
      priority: null,
      correlation_id: crypto.randomUUID(),
      parent_correlation_id: parentCorrelationId,
      idempotency_key: `cs-check-${check.id}`,
    };

    const csResult = runtime.clientCreateTask(JSON.stringify(csTaskRequest));
    if (csResult.success && csResult.data) {
      const taskData = csResult.data as { task_uuid: string };
      customerSuccessTaskUuid = taskData.task_uuid;
    }

    // Create payments task (namespace: payments)
    const paymentsTaskRequest: ClientTaskRequest = {
      name: 'payments_process_refund',
      namespace: 'payments',
      version: '1.0.0',
      context: {
        check_id: check.id,
        check_type,
        entity_type,
        entity_id,
        parameters: parameters || {},
        refund_amount: parameters?.refund_amount || '0.00',
        payment_method: parameters?.payment_method || 'credit_card',
        original_transaction_id: parameters?.transaction_id || crypto.randomUUID(),
      },
      initiator: 'bun-app',
      source_system: 'example-bun-app',
      reason: `Payment refund processing for ${entity_type}:${entity_id}`,
      tags: ['compliance', 'payments', 'refund'],
      requested_at: new Date().toISOString(),
      options: null,
      priority: null,
      correlation_id: crypto.randomUUID(),
      parent_correlation_id: parentCorrelationId,
      idempotency_key: `pay-check-${check.id}`,
    };

    const payResult = runtime.clientCreateTask(JSON.stringify(paymentsTaskRequest));
    if (payResult.success && payResult.data) {
      const taskData = payResult.data as { task_uuid: string };
      paymentsTaskUuid = taskData.task_uuid;
    }

    // Store the customer success task UUID as the primary reference
    if (customerSuccessTaskUuid) {
      await db
        .update(complianceChecks)
        .set({
          taskUuid: customerSuccessTaskUuid,
          status: 'processing',
          updatedAt: new Date(),
        })
        .where(eq(complianceChecks.id, check.id));
    }
  } catch (error) {
    console.error('Failed to create Tasker tasks for compliance check:', error);
  }

  return c.json(
    {
      id: check.id,
      check_type: check.checkType,
      entity_type: check.entityType,
      entity_id: check.entityId,
      parameters: check.parameters,
      status: customerSuccessTaskUuid ? 'processing' : 'pending',
      task_uuids: {
        customer_success: customerSuccessTaskUuid,
        payments: paymentsTaskUuid,
      },
      parent_correlation_id: parentCorrelationId,
      created_at: check.createdAt,
    },
    201,
  );
});

/**
 * GET /compliance/checks/:id
 *
 * Loads the compliance check record and fetches task statuses from
 * both namespaces for a combined cross-namespace view.
 */
complianceRoute.get('/:id', async (c) => {
  const id = parseInt(c.req.param('id'), 10);

  const check = await db.query.complianceChecks.findFirst({
    where: eq(complianceChecks.id, id),
  });

  if (!check) {
    return c.json({ error: 'Compliance check not found' }, 404);
  }

  let taskStatus = null;
  if (check.taskUuid) {
    try {
      const ffiLayer = new FfiLayer();
      await ffiLayer.load();
      const runtime = ffiLayer.getRuntime();
      const result = runtime.clientGetTask(check.taskUuid);

      if (result.success && result.data) {
        taskStatus = result.data;
      }
    } catch (error) {
      console.error('Failed to fetch task status:', error);
    }
  }

  return c.json({
    id: check.id,
    check_type: check.checkType,
    entity_type: check.entityType,
    entity_id: check.entityId,
    parameters: check.parameters,
    status: check.status,
    findings: check.findings,
    task_uuid: check.taskUuid,
    task_status: taskStatus,
    created_at: check.createdAt,
    updated_at: check.updatedAt,
  });
});
