/**
 * Polling helpers for verifying Tasker task completion via the orchestration API.
 *
 * Usage:
 *   import { waitForTaskCompletion, getTask, getTaskSteps } from './helpers';
 *   const task = await waitForTaskCompletion(taskUuid);
 *   expect(task.status).toBe('complete');
 */

const ORCHESTRATION_URL = process.env.ORCHESTRATION_URL || 'http://localhost:8080';
const API_KEY = process.env.TASKER_API_KEY || 'test-api-key-full-access';
const DEFAULT_TIMEOUT = 30_000; // ms
const POLL_INTERVAL = 1_000; // ms

// Truly terminal: no further progress possible.
const TERMINAL_STATUSES = new Set(['complete', 'error', 'cancelled']);

// Also terminal but may appear before retries finish -- give a grace period.
const FAILURE_STATUSES = new Set(['blocked_by_failures']);

export interface TaskStep {
  workflow_step_uuid: string;
  task_uuid: string;
  name: string;
  current_state: string;
  dependencies_satisfied: boolean;
  retry_eligible: boolean;
  ready_for_execution: boolean;
  total_parents: number;
  completed_parents: number;
  attempts: number;
  max_attempts: number;
  last_failure_at: string | null;
  last_attempted_at: string | null;
}

export interface TaskResponse {
  task_uuid: string;
  name: string;
  namespace: string;
  version: string;
  status: string;
  created_at: string;
  updated_at: string;
  completed_at: string | null;
  context: Record<string, unknown>;
  total_steps: number;
  pending_steps: number;
  in_progress_steps: number;
  completed_steps: number;
  failed_steps: number;
  completion_percentage: number;
  execution_status: string;
  health_status: string;
  steps: TaskStep[];
}

/**
 * Poll GET /v1/tasks/{uuid} until the task reaches a terminal status.
 *
 * A task in `blocked_by_failures` is given a 10-second grace period before
 * being treated as terminal, since steps may still be in waiting_for_retry.
 *
 * @param taskUuid - The task UUID to poll
 * @param timeout - Maximum milliseconds to wait (default 30000)
 * @param pollInterval - Milliseconds between polls (default 1000)
 * @returns The task response
 * @throws If the task does not complete within the timeout
 */
export async function waitForTaskCompletion(
  taskUuid: string,
  timeout = DEFAULT_TIMEOUT,
  pollInterval = POLL_INTERVAL,
): Promise<TaskResponse> {
  const deadline = Date.now() + timeout;
  let failureSeenAt: number | null = null;

  while (true) {
    const task = await getTask(taskUuid);

    // Immediately terminal
    if (TERMINAL_STATUSES.has(task.status)) {
      return task;
    }

    // Failure status with grace period
    if (FAILURE_STATUSES.has(task.status)) {
      if (failureSeenAt === null) {
        failureSeenAt = Date.now();
      }
      if (Date.now() - failureSeenAt >= 10_000) {
        return task;
      }
    } else {
      failureSeenAt = null;
    }

    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      throw new Error(
        `Task ${taskUuid} did not complete within ${timeout}ms. ` +
          `Last status: ${task.status}, completion: ${task.completion_percentage}%`,
      );
    }

    await new Promise((resolve) => setTimeout(resolve, Math.min(pollInterval, remaining)));
  }
}

/**
 * Fetch a single task from the orchestration API.
 */
export async function getTask(taskUuid: string): Promise<TaskResponse> {
  const res = await fetch(`${ORCHESTRATION_URL}/v1/tasks/${taskUuid}`, {
    headers: { 'X-API-Key': API_KEY },
  });

  if (!res.ok) {
    throw new Error(`GET /v1/tasks/${taskUuid} returned ${res.status}: ${await res.text()}`);
  }

  return res.json();
}

/**
 * Return the steps array from a task.
 */
export async function getTaskSteps(taskUuid: string): Promise<TaskStep[]> {
  const task = await getTask(taskUuid);
  return task.steps || [];
}

/**
 * Find a specific step by name within a task.
 */
export async function findStep(taskUuid: string, stepName: string): Promise<TaskStep | undefined> {
  const steps = await getTaskSteps(taskUuid);
  return steps.find((s) => s.name === stepName);
}
