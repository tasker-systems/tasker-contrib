import { Hono } from 'hono';
import { eq } from 'drizzle-orm';
import { db } from '../db/client';
import { analyticsJobs } from '../db/schema';
import { FfiLayer } from '@tasker-systems/tasker';
import type { ClientTaskRequest } from '@tasker-systems/tasker';

export const analyticsRoute = new Hono();

/**
 * POST /analytics/jobs
 *
 * Creates a new analytics job record, then creates a Tasker task to orchestrate
 * the data pipeline workflow (8 steps: 3 extracts -> 3 transforms -> aggregate -> insights).
 */
analyticsRoute.post('/', async (c) => {
  const body = await c.req.json();
  const { job_name, sources, parameters } = body;

  if (!job_name || !sources || !Array.isArray(sources) || sources.length === 0) {
    return c.json({ error: 'job_name and non-empty sources array are required' }, 400);
  }

  // Create domain record
  const [job] = await db
    .insert(analyticsJobs)
    .values({
      jobName: job_name,
      sources,
      parameters: parameters || {},
      status: 'pending',
    })
    .returning();

  // Create Tasker task for analytics pipeline
  let taskUuid: string | null = null;
  try {
    const ffiLayer = new FfiLayer();
    await ffiLayer.load();
    const runtime = ffiLayer.getRuntime();

    const taskRequest: ClientTaskRequest = {
      name: 'analytics_pipeline',
      namespace: 'default',
      version: '1.0.0',
      context: {
        job_id: job.id,
        job_name,
        sources,
        parameters: parameters || {},
        date_range: {
          start: parameters?.date_start || new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(),
          end: parameters?.date_end || new Date().toISOString(),
        },
      },
      initiator: 'bun-app',
      source_system: 'example-bun-app',
      reason: `Run analytics pipeline: ${job_name}`,
      tags: ['analytics', 'pipeline'],
      requested_at: new Date().toISOString(),
      options: null,
      priority: null,
      correlation_id: crypto.randomUUID(),
      parent_correlation_id: null,
      idempotency_key: `analytics-${job.id}`,
    };

    const result = runtime.clientCreateTask(JSON.stringify(taskRequest));

    if (result.success && result.data) {
      const taskData = result.data as { task_uuid: string };
      taskUuid = taskData.task_uuid;

      await db
        .update(analyticsJobs)
        .set({ taskUuid, status: 'processing', updatedAt: new Date() })
        .where(eq(analyticsJobs.id, job.id));
    }
  } catch (error) {
    console.error('Failed to create Tasker task for analytics job:', error);
  }

  return c.json(
    {
      id: job.id,
      job_name: job.jobName,
      sources: job.sources,
      parameters: job.parameters,
      status: taskUuid ? 'processing' : 'pending',
      task_uuid: taskUuid,
      created_at: job.createdAt,
    },
    201,
  );
});

/**
 * GET /analytics/jobs/:id
 *
 * Loads the analytics job record and, if a task_uuid exists, fetches the
 * current task status from Tasker for a combined view.
 */
analyticsRoute.get('/:id', async (c) => {
  const id = parseInt(c.req.param('id'), 10);

  const job = await db.query.analyticsJobs.findFirst({
    where: eq(analyticsJobs.id, id),
  });

  if (!job) {
    return c.json({ error: 'Analytics job not found' }, 404);
  }

  let taskStatus = null;
  if (job.taskUuid) {
    try {
      const ffiLayer = new FfiLayer();
      await ffiLayer.load();
      const runtime = ffiLayer.getRuntime();
      const result = runtime.clientGetTask(job.taskUuid);

      if (result.success && result.data) {
        taskStatus = result.data;
      }
    } catch (error) {
      console.error('Failed to fetch task status:', error);
    }
  }

  return c.json({
    id: job.id,
    job_name: job.jobName,
    sources: job.sources,
    parameters: job.parameters,
    status: job.status,
    result: job.result,
    task_uuid: job.taskUuid,
    task_status: taskStatus,
    created_at: job.createdAt,
    updated_at: job.updatedAt,
  });
});
