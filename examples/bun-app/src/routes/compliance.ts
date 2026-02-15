import { Hono } from 'hono';
import { eq } from 'drizzle-orm';
import { db } from '../db/client';
import { complianceChecks } from '../db/schema';
import { getTaskerClient } from '../tasker-client';

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
    const client = await getTaskerClient();

    // Create customer success task (namespace: customer_success_ts)
    const csTask = client.createTask({
      name: 'process_refund',
      namespace: 'customer_success_ts',
      context: {
        check_id: check.id,
        check_type,
        entity_type,
        entity_id,
        ticket_id: parameters?.ticket_id || `TKT-${check.id}`,
        customer_id: parameters?.customer_id || entity_id,
        customer_email: parameters?.customer_email || 'customer@example.com',
        refund_amount: parseFloat(parameters?.refund_amount) || 0,
        refund_reason: parameters?.reason || 'Customer request',
        correlation_id: parentCorrelationId,
      },
      initiator: 'bun-app',
      sourceSystem: 'example-bun-app',
      reason: `Customer success refund check for ${entity_type}:${entity_id}`,
      tags: ['compliance', 'customer-success', 'refund'],
      parentCorrelationId,
      idempotencyKey: `cs-check-${check.id}`,
    });
    customerSuccessTaskUuid = csTask.task_uuid;

    // Create payments task (namespace: payments_ts)
    const payTask = client.createTask({
      name: 'process_refund',
      namespace: 'payments_ts',
      context: {
        check_id: check.id,
        check_type,
        entity_type,
        entity_id,
        payment_id: parameters?.payment_id || `pay_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
        refund_amount: parseFloat(parameters?.refund_amount) || 0,
        customer_email: parameters?.customer_email || 'customer@example.com',
        partial_refund: parameters?.partial_refund || false,
        correlation_id: parentCorrelationId,
      },
      initiator: 'bun-app',
      sourceSystem: 'example-bun-app',
      reason: `Payment refund processing for ${entity_type}:${entity_id}`,
      tags: ['compliance', 'payments', 'refund'],
      parentCorrelationId,
      idempotencyKey: `pay-check-${check.id}`,
    });
    paymentsTaskUuid = payTask.task_uuid;

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
        customer_success_ts: customerSuccessTaskUuid,
        payments_ts: paymentsTaskUuid,
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
      const client = await getTaskerClient();
      taskStatus = client.getTask(check.taskUuid);
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
