import { Hono } from 'hono';
import { eq } from 'drizzle-orm';
import { db } from '../db/client';
import { orders } from '../db/schema';
import { FfiLayer, TaskerClient } from '@tasker-systems/tasker';

export const ordersRoute = new Hono();

/**
 * POST /orders
 *
 * Creates a new order record, then creates a Tasker task to orchestrate
 * the e-commerce order processing workflow (5 sequential steps).
 */
ordersRoute.post('/', async (c) => {
  const body = await c.req.json();
  const { customer_email, items, payment_info } = body;

  if (!customer_email || !items || !Array.isArray(items) || items.length === 0) {
    return c.json({ error: 'customer_email and non-empty items array are required' }, 400);
  }

  // Calculate total from items
  const total = items.reduce(
    (sum: number, item: { price: number; quantity: number }) =>
      sum + item.price * item.quantity,
    0,
  );

  // Create domain record
  const [order] = await db
    .insert(orders)
    .values({
      customerEmail: customer_email,
      items,
      total: total.toFixed(2),
      status: 'pending',
    })
    .returning();

  // Create Tasker task for order processing
  let taskUuid: string | null = null;
  try {
    const ffiLayer = new FfiLayer();
    await ffiLayer.load();
    const client = new TaskerClient(ffiLayer);

    const task = client.createTask({
      name: 'ecommerce_order_processing',
      context: {
        order_id: order.id,
        customer_email,
        cart_items: items,
        payment_info: payment_info || {},
      },
      initiator: 'bun-app',
      sourceSystem: 'example-bun-app',
      reason: `Process order #${order.id}`,
      tags: ['ecommerce', 'order'],
      idempotencyKey: `order-${order.id}`,
    });

    taskUuid = task.task_uuid;

    // Update order with task UUID
    await db
      .update(orders)
      .set({ taskUuid, status: 'processing', updatedAt: new Date() })
      .where(eq(orders.id, order.id));
  } catch (error) {
    console.error('Failed to create Tasker task for order:', error);
  }

  return c.json(
    {
      id: order.id,
      customer_email: order.customerEmail,
      items: order.items,
      total: order.total,
      status: taskUuid ? 'processing' : 'pending',
      task_uuid: taskUuid,
      created_at: order.createdAt,
    },
    201,
  );
});

/**
 * GET /orders/:id
 *
 * Loads the order record and, if a task_uuid exists, fetches the
 * current task status from Tasker for a combined view.
 */
ordersRoute.get('/:id', async (c) => {
  const id = parseInt(c.req.param('id'), 10);

  const order = await db.query.orders.findFirst({
    where: eq(orders.id, id),
  });

  if (!order) {
    return c.json({ error: 'Order not found' }, 404);
  }

  let taskStatus = null;
  if (order.taskUuid) {
    try {
      const ffiLayer = new FfiLayer();
      await ffiLayer.load();
      const client = new TaskerClient(ffiLayer);
      taskStatus = client.getTask(order.taskUuid);
    } catch (error) {
      console.error('Failed to fetch task status:', error);
    }
  }

  return c.json({
    id: order.id,
    customer_email: order.customerEmail,
    items: order.items,
    total: order.total,
    status: order.status,
    task_uuid: order.taskUuid,
    task_status: taskStatus,
    created_at: order.createdAt,
    updated_at: order.updatedAt,
  });
});
