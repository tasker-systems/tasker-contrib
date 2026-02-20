/**
 * Microservices user registration step handlers.
 *
 * 5 steps forming a diamond dependency pattern:
 *   CreateUserAccount
 *        |-- SetupBillingProfile  --|
 *        |-- InitializePreferences -|
 *                                    |-- SendWelcomeSequence -> UpdateUserStatus
 *
 * Thin DSL wrappers that delegate to ../services/microservices for business logic.
 */

import { defineHandler, PermanentError } from '@tasker-systems/tasker';
import * as svc from '../services/microservices';

export const CreateUserHandler = defineHandler(
  'Microservices.StepHandlers.CreateUserHandler',
  { inputs: { email: 'email', username: 'username', plan: 'plan', metadata: 'metadata' } },
  async ({ email, username, plan, metadata }) => {
    if (!email) {
      throw new PermanentError('Email is required but was not provided');
    }

    if (!username) {
      throw new PermanentError('Username is required but was not provided');
    }

    return svc.createUserAccount({
      email: email as string,
      username: username as string,
      plan: plan as string | undefined,
      metadata: metadata as Record<string, unknown> | undefined,
    });
  },
);

export const SetupBillingHandler = defineHandler(
  'Microservices.StepHandlers.SetupBillingHandler',
  { depends: { userData: 'create_user_account' } },
  async ({ userData }) => svc.setupBilling(userData as Record<string, unknown>),
);

export const InitPreferencesHandler = defineHandler(
  'Microservices.StepHandlers.InitPreferencesHandler',
  {
    depends: { userData: 'create_user_account' },
    inputs: { metadata: 'metadata' },
  },
  async ({ userData, metadata }) =>
    svc.initPreferences(
      userData as Record<string, unknown>,
      metadata as Record<string, unknown> | undefined,
    ),
);

export const SendWelcomeHandler = defineHandler(
  'Microservices.StepHandlers.SendWelcomeHandler',
  {
    depends: {
      userData: 'create_user_account',
      billingData: 'setup_billing_profile',
      preferencesData: 'initialize_preferences',
    },
  },
  async ({ userData, billingData, preferencesData }) =>
    svc.sendWelcome(
      userData as Record<string, unknown>,
      billingData as Record<string, unknown>,
      preferencesData as Record<string, unknown>,
    ),
);

export const UpdateStatusHandler = defineHandler(
  'Microservices.StepHandlers.UpdateStatusHandler',
  {
    depends: {
      userData: 'create_user_account',
      billingData: 'setup_billing_profile',
      preferencesData: 'initialize_preferences',
      welcomeData: 'send_welcome_sequence',
    },
  },
  async ({ userData, billingData, preferencesData, welcomeData }) =>
    svc.updateStatus(
      userData as Record<string, unknown>,
      billingData as Record<string, unknown>,
      preferencesData as Record<string, unknown>,
      welcomeData as Record<string, unknown>,
    ),
);
