import { jsonb, numeric, pgTable, serial, timestamp, uuid, varchar } from 'drizzle-orm/pg-core';

export const orders = pgTable('orders', {
  id: serial('id').primaryKey(),
  customerEmail: varchar('customer_email', { length: 255 }).notNull(),
  items: jsonb('items').notNull(),
  total: numeric('total', { precision: 10, scale: 2 }).notNull().default('0'),
  status: varchar('status', { length: 50 }).notNull().default('pending'),
  taskUuid: uuid('task_uuid'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
});

export const analyticsJobs = pgTable('analytics_jobs', {
  id: serial('id').primaryKey(),
  jobName: varchar('job_name', { length: 255 }).notNull(),
  sources: jsonb('sources').notNull(),
  parameters: jsonb('parameters').notNull().default({}),
  status: varchar('status', { length: 50 }).notNull().default('pending'),
  result: jsonb('result'),
  taskUuid: uuid('task_uuid'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
});

export const serviceRequests = pgTable('service_requests', {
  id: serial('id').primaryKey(),
  username: varchar('username', { length: 255 }).notNull(),
  email: varchar('email', { length: 255 }).notNull(),
  plan: varchar('plan', { length: 50 }).notNull().default('free'),
  metadata: jsonb('metadata').notNull().default({}),
  status: varchar('status', { length: 50 }).notNull().default('pending'),
  taskUuid: uuid('task_uuid'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
});

export const complianceChecks = pgTable('compliance_checks', {
  id: serial('id').primaryKey(),
  checkType: varchar('check_type', { length: 100 }).notNull(),
  entityType: varchar('entity_type', { length: 100 }).notNull(),
  entityId: varchar('entity_id', { length: 255 }).notNull(),
  parameters: jsonb('parameters').notNull().default({}),
  status: varchar('status', { length: 50 }).notNull().default('pending'),
  findings: jsonb('findings'),
  taskUuid: uuid('task_uuid'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
});
