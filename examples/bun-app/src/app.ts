import { Hono } from 'hono';
import { logger } from 'hono/logger';
import { ordersRoute } from './routes/orders';
import { analyticsRoute } from './routes/analytics';
import { servicesRoute } from './routes/services';
import { complianceRoute } from './routes/compliance';

/**
 * Create and configure the Hono application with all routes.
 *
 * Separated from index.ts so tests can import the app directly
 * and use `app.request()` without starting a server.
 */
export function createApp(): Hono {
  const app = new Hono();

  // Middleware
  app.use('*', logger());

  // Health check
  app.get('/health', (c) => c.json({ status: 'ok', timestamp: new Date().toISOString() }));

  // Mount routes
  app.route('/orders', ordersRoute);
  app.route('/analytics/jobs', analyticsRoute);
  app.route('/services/requests', servicesRoute);
  app.route('/compliance/checks', complianceRoute);

  return app;
}
