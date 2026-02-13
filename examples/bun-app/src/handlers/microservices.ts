import {
  StepHandler,
  type StepContext,
  type StepHandlerResult,
  ErrorType,
} from '@tasker-systems/tasker';

// ---------------------------------------------------------------------------
// Step 1: CreateUser (first step, no dependencies)
// ---------------------------------------------------------------------------

export class CreateUserHandler extends StepHandler {
  static handlerName = 'Microservices.StepHandlers.CreateUserHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const username = context.getInput<string>('username');
      const email = context.getInput<string>('email');
      const plan = context.getInput<string>('plan') || 'free';

      if (!username || !email) {
        return this.failure(
          'username and email are required',
          ErrorType.VALIDATION_ERROR,
          false,
        );
      }

      // Validate email format
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(email)) {
        return this.failure(
          `Invalid email format: ${email}`,
          ErrorType.VALIDATION_ERROR,
          false,
        );
      }

      // Simulate user creation in auth service
      const userId = crypto.randomUUID();
      const apiKey = `ak_${crypto.randomUUID().replace(/-/g, '').substring(0, 32)}`;
      const passwordHash = crypto.randomUUID().replace(/-/g, '');

      return this.success(
        {
          user_id: userId,
          username,
          email,
          plan,
          api_key: apiKey,
          password_hash_algorithm: 'argon2id',
          password_hash_preview: `$argon2id$v=19$...${passwordHash.substring(0, 8)}`,
          email_verified: false,
          account_status: 'pending_verification',
          created_at: new Date().toISOString(),
          auth_provider: 'internal',
        },
        { user_creation_ms: Math.random() * 100 + 30 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 2: SetupBilling (depends on CreateUser, parallel with InitPreferences)
// ---------------------------------------------------------------------------

export class SetupBillingHandler extends StepHandler {
  static handlerName = 'Microservices.StepHandlers.SetupBillingHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const userResult = context.getDependencyResult('create_user') as Record<string, unknown>;

      if (!userResult) {
        return this.failure('Missing user creation result', ErrorType.HANDLER_ERROR, true);
      }

      const userId = userResult.user_id as string;
      const plan = userResult.plan as string;
      const email = userResult.email as string;

      // Simulate billing account creation with Stripe-like semantics
      const customerId = `cus_${crypto.randomUUID().replace(/-/g, '').substring(0, 14)}`;
      const subscriptionId = plan !== 'free'
        ? `sub_${crypto.randomUUID().replace(/-/g, '').substring(0, 14)}`
        : null;

      const planPricing: Record<string, { monthly: number; trial_days: number }> = {
        free: { monthly: 0, trial_days: 0 },
        basic: { monthly: 9.99, trial_days: 14 },
        standard: { monthly: 29.99, trial_days: 14 },
        premium: { monthly: 99.99, trial_days: 30 },
      };

      const pricing = planPricing[plan] || planPricing.free;
      const trialEnd = pricing.trial_days > 0
        ? new Date(Date.now() + pricing.trial_days * 24 * 60 * 60 * 1000).toISOString()
        : null;

      return this.success(
        {
          customer_id: customerId,
          user_id: userId,
          email,
          subscription_id: subscriptionId,
          plan,
          billing_status: subscriptionId ? 'trialing' : 'free_tier',
          monthly_amount: pricing.monthly,
          currency: 'usd',
          trial_end: trialEnd,
          payment_method_required: plan !== 'free',
          invoice_settings: {
            default_payment_method: null,
            footer: `Account: ${customerId}`,
          },
          billing_provider: 'stripe_simulator',
          created_at: new Date().toISOString(),
        },
        { billing_setup_ms: Math.random() * 200 + 80 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.RETRYABLE_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 3: InitPreferences (depends on CreateUser, parallel with SetupBilling)
// ---------------------------------------------------------------------------

export class InitPreferencesHandler extends StepHandler {
  static handlerName = 'Microservices.StepHandlers.InitPreferencesHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const userResult = context.getDependencyResult('create_user') as Record<string, unknown>;
      const metadata = context.getInput<Record<string, unknown>>('metadata') || {};

      if (!userResult) {
        return this.failure('Missing user creation result', ErrorType.HANDLER_ERROR, true);
      }

      const userId = userResult.user_id as string;
      const plan = userResult.plan as string;

      // Build default preferences based on plan tier
      const featureFlags: Record<string, boolean> = {
        dark_mode: true,
        email_notifications: true,
        push_notifications: plan !== 'free',
        advanced_analytics: plan === 'premium' || plan === 'standard',
        api_access: plan !== 'free',
        custom_branding: plan === 'premium',
        sso_enabled: plan === 'premium',
        export_enabled: plan !== 'free',
      };

      const notificationPreferences = {
        email: {
          marketing: false,
          product_updates: true,
          security_alerts: true,
          billing: true,
          weekly_digest: plan !== 'free',
        },
        in_app: {
          mentions: true,
          task_updates: true,
          system_alerts: true,
        },
      };

      // Merge any custom preferences from metadata
      const timezone = (metadata.timezone as string) || 'UTC';
      const locale = (metadata.locale as string) || 'en-US';

      return this.success(
        {
          user_id: userId,
          preferences_id: crypto.randomUUID(),
          feature_flags: featureFlags,
          enabled_features_count: Object.values(featureFlags).filter(Boolean).length,
          notification_preferences: notificationPreferences,
          display: {
            timezone,
            locale,
            date_format: locale.startsWith('en-US') ? 'MM/DD/YYYY' : 'DD/MM/YYYY',
            theme: 'system',
          },
          onboarding: {
            completed: false,
            current_step: 1,
            total_steps: 5,
          },
          created_at: new Date().toISOString(),
        },
        { preferences_setup_ms: Math.random() * 60 + 15 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 4: SendWelcome (depends on SetupBilling and InitPreferences)
// ---------------------------------------------------------------------------

export class SendWelcomeHandler extends StepHandler {
  static handlerName = 'Microservices.StepHandlers.SendWelcomeHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const userResult = context.getDependencyResult('create_user') as Record<string, unknown>;
      const billingResult = context.getDependencyResult('setup_billing') as Record<string, unknown>;
      const preferencesResult = context.getDependencyResult('init_preferences') as Record<string, unknown>;

      if (!userResult || !billingResult || !preferencesResult) {
        return this.failure(
          'Missing required dependency results',
          ErrorType.HANDLER_ERROR,
          true,
        );
      }

      const email = userResult.email as string;
      const username = userResult.username as string;
      const plan = userResult.plan as string;
      const trialEnd = billingResult.trial_end as string | null;
      const enabledFeatures = preferencesResult.enabled_features_count as number;

      // Simulate sending multi-channel welcome messages
      const emailMessageId = crypto.randomUUID();
      const slackMessageTs = `${Date.now()}.${Math.floor(Math.random() * 1000000)}`;

      const welcomeActions = [
        {
          channel: 'email',
          message_id: emailMessageId,
          template: 'welcome_v4',
          subject: `Welcome to the platform, ${username}!`,
          status: 'queued',
        },
        {
          channel: 'in_app',
          message_id: crypto.randomUUID(),
          template: 'onboarding_checklist',
          status: 'delivered',
        },
      ];

      if (plan !== 'free') {
        welcomeActions.push({
          channel: 'slack',
          message_id: slackMessageTs,
          template: 'premium_welcome',
          subject: `New ${plan} customer: ${username}`,
          status: 'queued',
        });
      }

      return this.success(
        {
          recipient: email,
          username,
          welcome_actions: welcomeActions,
          messages_sent: welcomeActions.length,
          personalization: {
            plan_name: plan,
            trial_end: trialEnd,
            features_enabled: enabledFeatures,
            getting_started_url: `https://app.example.com/onboarding?user=${username}`,
          },
          sent_at: new Date().toISOString(),
        },
        { notification_dispatch_ms: Math.random() * 150 + 40 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.RETRYABLE_ERROR,
        true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Step 5: UpdateStatus (depends on SendWelcome -- final step)
// ---------------------------------------------------------------------------

export class UpdateStatusHandler extends StepHandler {
  static handlerName = 'Microservices.StepHandlers.UpdateStatusHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const userResult = context.getDependencyResult('create_user') as Record<string, unknown>;
      const billingResult = context.getDependencyResult('setup_billing') as Record<string, unknown>;
      const welcomeResult = context.getDependencyResult('send_welcome') as Record<string, unknown>;

      if (!userResult || !billingResult || !welcomeResult) {
        return this.failure(
          'Missing required dependency results',
          ErrorType.HANDLER_ERROR,
          true,
        );
      }

      const userId = userResult.user_id as string;
      const username = userResult.username as string;
      const plan = userResult.plan as string;
      const customerId = billingResult.customer_id as string;
      const messagesSent = welcomeResult.messages_sent as number;

      // Simulate updating user status across all microservices
      const statusUpdates = [
        { service: 'auth_service', status: 'active', updated: true },
        { service: 'billing_service', status: 'configured', updated: true },
        { service: 'preferences_service', status: 'initialized', updated: true },
        { service: 'notification_service', status: 'subscribed', updated: true },
        { service: 'analytics_service', status: 'tracking', updated: true },
      ];

      return this.success(
        {
          user_id: userId,
          username,
          final_status: 'active',
          registration_complete: true,
          service_statuses: statusUpdates,
          services_updated: statusUpdates.length,
          summary: {
            plan,
            billing_customer_id: customerId,
            welcome_messages_sent: messagesSent,
            account_ready: true,
            login_url: `https://app.example.com/login`,
          },
          completed_at: new Date().toISOString(),
        },
        { status_update_ms: Math.random() * 100 + 20 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}
