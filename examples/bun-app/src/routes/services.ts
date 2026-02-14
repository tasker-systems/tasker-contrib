import { Hono } from 'hono';
import { eq } from 'drizzle-orm';
import { db } from '../db/client';
import { serviceRequests } from '../db/schema';
import { FfiLayer, TaskerClient } from '@tasker-systems/tasker';

export const servicesRoute = new Hono();

/**
 * POST /services/requests
 *
 * Creates a new service request record, then creates a Tasker task to orchestrate
 * the microservices user registration workflow (5 steps with diamond pattern).
 */
servicesRoute.post('/', async (c) => {
  const body = await c.req.json();
  const { username, email, plan, metadata } = body;

  if (!username || !email) {
    return c.json({ error: 'username and email are required' }, 400);
  }

  // Create domain record
  const [request] = await db
    .insert(serviceRequests)
    .values({
      username,
      email,
      plan: plan || 'free',
      metadata: metadata || {},
      status: 'pending',
    })
    .returning();

  // Create Tasker task for user registration
  let taskUuid: string | null = null;
  try {
    const ffiLayer = new FfiLayer();
    await ffiLayer.load();
    const client = new TaskerClient(ffiLayer);

    const task = client.createTask({
      name: 'user_registration',
      context: {
        request_id: request.id,
        username,
        email,
        plan: plan || 'free',
        metadata: metadata || {},
      },
      initiator: 'bun-app',
      sourceSystem: 'example-bun-app',
      reason: `Register user: ${username}`,
      tags: ['microservices', 'registration'],
      idempotencyKey: `registration-${request.id}`,
    });

    taskUuid = task.task_uuid;

    await db
      .update(serviceRequests)
      .set({ taskUuid, status: 'processing', updatedAt: new Date() })
      .where(eq(serviceRequests.id, request.id));
  } catch (error) {
    console.error('Failed to create Tasker task for service request:', error);
  }

  return c.json(
    {
      id: request.id,
      username: request.username,
      email: request.email,
      plan: request.plan,
      status: taskUuid ? 'processing' : 'pending',
      task_uuid: taskUuid,
      created_at: request.createdAt,
    },
    201,
  );
});

/**
 * GET /services/requests/:id
 *
 * Loads the service request record and, if a task_uuid exists, fetches the
 * current task status from Tasker for a combined view.
 */
servicesRoute.get('/:id', async (c) => {
  const id = parseInt(c.req.param('id'), 10);

  const request = await db.query.serviceRequests.findFirst({
    where: eq(serviceRequests.id, id),
  });

  if (!request) {
    return c.json({ error: 'Service request not found' }, 404);
  }

  let taskStatus = null;
  if (request.taskUuid) {
    try {
      const ffiLayer = new FfiLayer();
      await ffiLayer.load();
      const client = new TaskerClient(ffiLayer);
      taskStatus = client.getTask(request.taskUuid);
    } catch (error) {
      console.error('Failed to fetch task status:', error);
    }
  }

  return c.json({
    id: request.id,
    username: request.username,
    email: request.email,
    plan: request.plan,
    metadata: request.metadata,
    status: request.status,
    task_uuid: request.taskUuid,
    task_status: taskStatus,
    created_at: request.createdAt,
    updated_at: request.updatedAt,
  });
});
