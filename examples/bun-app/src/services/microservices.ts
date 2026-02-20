/**
 * Microservices user registration business logic.
 *
 * Pure functions that create user accounts, set up billing profiles,
 * initialize preferences, send welcome sequences, and update user status.
 * No Tasker types -- just plain objects in, plain objects out.
 *
 * Diamond dependency pattern:
 *   CreateUserAccount
 *        |-- SetupBillingProfile  --|
 *        |-- InitializePreferences -|
 *                                    |-- SendWelcomeSequence -> UpdateUserStatus
 */

import { PermanentError } from '@tasker-systems/tasker';

import type {
  CreateUserAccountInput,
  BillingTier,
  MicroservicesCreateUserResult,
  MicroservicesSetupBillingResult,
  MicroservicesInitPreferencesResult,
  MicroservicesSendWelcomeResult,
  MicroservicesUpdateStatusResult,
} from './types';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const BILLING_TIERS: Record<string, BillingTier> = {
  free: { price: 0, features: ['basic_features'], billing_required: false },
  pro: {
    price: 29.99,
    features: ['basic_features', 'advanced_analytics'],
    billing_required: true,
  },
  enterprise: {
    price: 299.99,
    features: [
      'basic_features',
      'advanced_analytics',
      'priority_support',
      'custom_integrations',
    ],
    billing_required: true,
  },
  basic: { price: 9.99, features: ['basic_features'], billing_required: true },
  standard: {
    price: 29.99,
    features: ['basic_features', 'advanced_analytics'],
    billing_required: true,
  },
  premium: {
    price: 99.99,
    features: ['basic_features', 'advanced_analytics', 'priority_support'],
    billing_required: true,
  },
};

const DEFAULT_PREFERENCES: Record<string, Record<string, unknown>> = {
  free: {
    email_notifications: true,
    marketing_emails: false,
    product_updates: true,
    weekly_digest: false,
    theme: 'light',
    language: 'en',
    timezone: 'UTC',
  },
  pro: {
    email_notifications: true,
    marketing_emails: true,
    product_updates: true,
    weekly_digest: true,
    theme: 'dark',
    language: 'en',
    timezone: 'UTC',
    api_notifications: true,
  },
  enterprise: {
    email_notifications: true,
    marketing_emails: true,
    product_updates: true,
    weekly_digest: true,
    theme: 'dark',
    language: 'en',
    timezone: 'UTC',
    api_notifications: true,
    audit_logs: true,
    advanced_reports: true,
  },
};

// ---------------------------------------------------------------------------
// Service functions
// ---------------------------------------------------------------------------

export function createUserAccount(
  input: CreateUserAccountInput,
): MicroservicesCreateUserResult {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(input.email)) {
    throw new PermanentError(`Invalid email format: ${input.email}`);
  }

  const source = (input.metadata?.referral_source as string) || 'web';
  const userId = crypto.randomUUID();
  const now = new Date().toISOString();
  const apiKey = `ak_${crypto.randomUUID().replace(/-/g, '').substring(0, 32)}`;

  return {
    user_id: userId,
    email: input.email,
    name: input.username,
    plan: input.plan || 'free',
    phone: null,
    source,
    status: 'created',
    created_at: now,
    api_key: apiKey,
    auth_provider: 'internal',
  };
}

export function setupBilling(userData: Record<string, unknown>): MicroservicesSetupBillingResult {
  if (!userData) {
    throw new PermanentError('User data not found from create_user_account step');
  }

  const userId = userData.user_id as string;
  const plan = (userData.plan as string) || 'free';
  const tierConfig = BILLING_TIERS[plan] || BILLING_TIERS.free;

  if (tierConfig.billing_required) {
    const now = new Date();
    const nextBilling = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);

    return {
      billing_id: `billing_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
      user_id: userId,
      plan,
      price: tierConfig.price,
      currency: 'USD',
      billing_cycle: 'monthly',
      features: tierConfig.features,
      status: 'active',
      next_billing_date: nextBilling.toISOString(),
      created_at: now.toISOString(),
    };
  } else {
    return {
      user_id: userId,
      plan,
      billing_required: false,
      status: 'skipped_free_plan',
      message: 'Free plan users do not require billing setup',
    };
  }
}

export function initPreferences(
  userData: Record<string, unknown>,
  metadata: Record<string, unknown> | undefined,
): MicroservicesInitPreferencesResult {
  if (!userData) {
    throw new PermanentError('User data not found from create_user_account step');
  }

  const userId = userData.user_id as string;
  const plan = (userData.plan as string) || 'free';
  const customPrefs = ((metadata?.preferences as Record<string, unknown>) || {});
  const defaultPrefs = DEFAULT_PREFERENCES[plan] || DEFAULT_PREFERENCES.free;
  const finalPrefs = { ...defaultPrefs, ...customPrefs };
  const now = new Date().toISOString();

  return {
    preferences_id: crypto.randomUUID(),
    user_id: userId,
    plan,
    preferences: finalPrefs,
    defaults_applied: Object.keys(defaultPrefs).length,
    customizations: Object.keys(customPrefs).length,
    status: 'active',
    created_at: now,
    updated_at: now,
  };
}

export function sendWelcome(
  userData: Record<string, unknown>,
  billingData: Record<string, unknown>,
  preferencesData: Record<string, unknown>,
): MicroservicesSendWelcomeResult {
  const missing: string[] = [];
  if (!userData) missing.push('create_user_account');
  if (!billingData) missing.push('setup_billing_profile');
  if (!preferencesData) missing.push('initialize_preferences');

  if (missing.length > 0) {
    throw new PermanentError(`Missing results from steps: ${missing.join(', ')}`);
  }

  const userId = userData.user_id as string;
  const email = userData.email as string;
  const plan = (userData.plan as string) || 'free';
  const prefs = (preferencesData.preferences || {}) as Record<string, unknown>;

  const channelsUsed: string[] = [];
  const now = new Date().toISOString();

  if (prefs.email_notifications !== false) {
    channelsUsed.push('email');
  }

  channelsUsed.push('in_app');

  if (plan === 'enterprise') {
    channelsUsed.push('sms');
  }

  return {
    user_id: userId,
    plan,
    channels_used: channelsUsed,
    messages_sent: channelsUsed.length,
    welcome_sequence_id: crypto.randomUUID(),
    status: 'sent',
    sent_at: now,
    recipient: email,
  };
}

export function updateStatus(
  userData: Record<string, unknown>,
  billingData: Record<string, unknown>,
  preferencesData: Record<string, unknown>,
  welcomeData: Record<string, unknown>,
): MicroservicesUpdateStatusResult {
  const missing: string[] = [];
  if (!userData) missing.push('create_user_account');
  if (!billingData) missing.push('setup_billing_profile');
  if (!preferencesData) missing.push('initialize_preferences');
  if (!welcomeData) missing.push('send_welcome_sequence');

  if (missing.length > 0) {
    throw new PermanentError(
      `Cannot complete registration: missing results from steps: ${missing.join(', ')}`,
    );
  }

  const userId = userData.user_id as string;
  const email = userData.email as string;
  const plan = (userData.plan as string) || 'free';

  const prefs = (preferencesData.preferences || {}) as Record<string, unknown>;
  const registrationSummary: Record<string, unknown> = {
    user_id: userId,
    email,
    plan,
    registration_status: 'complete',
    preferences_count: Object.keys(prefs).length,
    welcome_sent: true,
    notification_channels: welcomeData.channels_used,
    user_created_at: userData.created_at,
    registration_completed_at: new Date().toISOString(),
  };

  if (plan !== 'free' && billingData.billing_id) {
    registrationSummary.billing_id = billingData.billing_id;
    registrationSummary.next_billing_date = billingData.next_billing_date;
  }

  const now = new Date().toISOString();

  return {
    user_id: userId,
    status: 'active',
    plan,
    registration_summary: registrationSummary,
    activation_timestamp: now,
    all_services_coordinated: true,
    services_completed: [
      'user_service',
      'billing_service',
      'preferences_service',
      'notification_service',
    ],
  };
}
