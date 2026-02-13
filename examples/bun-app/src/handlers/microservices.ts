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
  static handlerName = 'Microservices.StepHandlers.CreateUserAccountHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      // TAS-137: Use getInput() for task context access (matches source: reads user_info object)
      const userInfo = (context.getInput('user_info') || {}) as {
        email?: string;
        name?: string;
        plan?: string;
        phone?: string;
        source?: string;
        preferences?: Record<string, unknown>;
      };

      if (!userInfo.email) {
        return this.failure(
          'Email is required but was not provided',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      if (!userInfo.name) {
        return this.failure(
          'Name is required but was not provided',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      // Validate email format
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(userInfo.email)) {
        return this.failure(
          `Invalid email format: ${userInfo.email}`,
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const plan = userInfo.plan || 'free';
      const source = userInfo.source || 'web';

      // Simulate user creation in auth service
      const userId = crypto.randomUUID();
      const now = new Date().toISOString();
      const apiKey = `ak_${crypto.randomUUID().replace(/-/g, '').substring(0, 32)}`;

      return this.success(
        {
          user_id: userId,
          email: userInfo.email,
          name: userInfo.name,
          plan,
          phone: userInfo.phone,
          source,
          status: 'created',
          created_at: now,
          api_key: apiKey,
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
  static handlerName = 'Microservices.StepHandlers.SetupBillingProfileHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const userData = context.getDependencyResult('create_user_account') as Record<string, unknown>;

      if (!userData) {
        return this.failure(
          'User data not found from create_user_account step',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const userId = userData.user_id as string;
      const plan = (userData.plan as string) || 'free';

      // Billing tiers configuration
      const billingTiers: Record<string, { price: number; features: string[]; billing_required: boolean }> = {
        free: { price: 0, features: ['basic_features'], billing_required: false },
        pro: { price: 29.99, features: ['basic_features', 'advanced_analytics'], billing_required: true },
        enterprise: { price: 299.99, features: ['basic_features', 'advanced_analytics', 'priority_support', 'custom_integrations'], billing_required: true },
        basic: { price: 9.99, features: ['basic_features'], billing_required: true },
        standard: { price: 29.99, features: ['basic_features', 'advanced_analytics'], billing_required: true },
        premium: { price: 99.99, features: ['basic_features', 'advanced_analytics', 'priority_support'], billing_required: true },
      };

      const tierConfig = billingTiers[plan] || billingTiers.free;

      if (tierConfig.billing_required) {
        // Paid plan - create billing profile
        const now = new Date();
        const nextBilling = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);

        return this.success(
          {
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
          },
          { billing_setup_ms: Math.random() * 200 + 80 },
        );
      } else {
        // Free plan - graceful degradation
        return this.success(
          {
            user_id: userId,
            plan,
            billing_required: false,
            status: 'skipped_free_plan',
            message: 'Free plan users do not require billing setup',
          },
          { billing_setup_ms: Math.random() * 200 + 80 },
        );
      }
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
  static handlerName = 'Microservices.StepHandlers.InitializePreferencesHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const userData = context.getDependencyResult('create_user_account') as Record<string, unknown>;

      if (!userData) {
        return this.failure(
          'User data not found from create_user_account step',
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const userId = userData.user_id as string;
      const plan = (userData.plan as string) || 'free';

      // Get custom preferences from task input (matches source: reads user_info)
      const userInfo = (context.getInput('user_info') || {}) as { preferences?: Record<string, unknown> };
      const customPrefs = userInfo.preferences || {};

      // Default preferences by plan
      const defaultPreferences: Record<string, Record<string, unknown>> = {
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

      const defaultPrefs = defaultPreferences[plan] || defaultPreferences.free;
      const finalPrefs = { ...defaultPrefs, ...customPrefs };

      const now = new Date().toISOString();

      return this.success(
        {
          preferences_id: crypto.randomUUID(),
          user_id: userId,
          plan,
          preferences: finalPrefs,
          defaults_applied: Object.keys(defaultPrefs).length,
          customizations: Object.keys(customPrefs).length,
          status: 'active',
          created_at: now,
          updated_at: now,
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
  static handlerName = 'Microservices.StepHandlers.SendWelcomeSequenceHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const userData = context.getDependencyResult('create_user_account') as Record<string, unknown>;
      const billingData = context.getDependencyResult('setup_billing_profile') as Record<string, unknown>;
      const preferencesData = context.getDependencyResult('initialize_preferences') as Record<string, unknown>;

      // Validate all prior steps
      const missing: string[] = [];
      if (!userData) missing.push('create_user_account');
      if (!billingData) missing.push('setup_billing_profile');
      if (!preferencesData) missing.push('initialize_preferences');

      if (missing.length > 0) {
        return this.failure(
          `Missing results from steps: ${missing.join(', ')}`,
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const userId = userData!.user_id as string;
      const email = userData!.email as string;
      const plan = (userData!.plan as string) || 'free';
      const prefs = (preferencesData!.preferences || {}) as Record<string, unknown>;

      const channelsUsed: string[] = [];
      const now = new Date().toISOString();

      // Email (if enabled)
      if (prefs.email_notifications !== false) {
        channelsUsed.push('email');
      }

      // In-app notification (always)
      channelsUsed.push('in_app');

      // SMS (enterprise only)
      if (plan === 'enterprise') {
        channelsUsed.push('sms');
      }

      return this.success(
        {
          user_id: userId,
          plan,
          channels_used: channelsUsed,
          messages_sent: channelsUsed.length,
          welcome_sequence_id: crypto.randomUUID(),
          status: 'sent',
          sent_at: now,
          recipient: email,
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
  static handlerName = 'Microservices.StepHandlers.UpdateUserStatusHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      // Collect results from all prior steps
      const userData = context.getDependencyResult('create_user_account') as Record<string, unknown>;
      const billingData = context.getDependencyResult('setup_billing_profile') as Record<string, unknown>;
      const preferencesData = context.getDependencyResult('initialize_preferences') as Record<string, unknown>;
      const welcomeData = context.getDependencyResult('send_welcome_sequence') as Record<string, unknown>;

      // Validate all prior steps completed
      const missing: string[] = [];
      if (!userData) missing.push('create_user_account');
      if (!billingData) missing.push('setup_billing_profile');
      if (!preferencesData) missing.push('initialize_preferences');
      if (!welcomeData) missing.push('send_welcome_sequence');

      if (missing.length > 0) {
        return this.failure(
          `Cannot complete registration: missing results from steps: ${missing.join(', ')}`,
          ErrorType.PERMANENT_ERROR,
          false,
        );
      }

      const userId = userData!.user_id as string;
      const email = userData!.email as string;
      const plan = (userData!.plan as string) || 'free';

      // Build registration summary (matching source output keys)
      const prefs = (preferencesData!.preferences || {}) as Record<string, unknown>;
      const registrationSummary: Record<string, unknown> = {
        user_id: userId,
        email,
        plan,
        registration_status: 'complete',
        preferences_count: Object.keys(prefs).length,
        welcome_sent: true,
        notification_channels: welcomeData!.channels_used,
        user_created_at: userData!.created_at,
        registration_completed_at: new Date().toISOString(),
      };

      if (plan !== 'free' && billingData!.billing_id) {
        registrationSummary.billing_id = billingData!.billing_id;
        registrationSummary.next_billing_date = billingData!.next_billing_date;
      }

      const now = new Date().toISOString();

      return this.success(
        {
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
