//! # Microservices User Registration Handlers
//!
//! Native Rust implementation of the microservices user registration workflow.
//! Demonstrates a diamond pattern with parallel branches converging.
//!
//! ## Steps (Diamond Pattern)
//!
//! 1. **microservices_create_user_account**: Validate email, generate user ID
//! 2. **microservices_setup_billing_profile**: Plan tiers (free/pro/enterprise) [parallel]
//! 3. **microservices_initialize_preferences**: Plan-based defaults [parallel]
//! 4. **microservices_send_welcome_sequence**: Multi-channel welcome messages [convergence]
//! 5. **microservices_update_user_status**: Activate user account

use crate::types::microservices::*;
use serde_json::{json, Value};
use std::collections::HashMap;
use tracing::info;
use uuid::Uuid;

// ============================================================================
// Step 1: Create User Account
// ============================================================================

/// Validates the user email, checks for duplicates, and creates a new user account.
pub fn create_user_account(context: &Value) -> Result<Value, String> {
    let input: UserRegistrationInput = serde_json::from_value(context.clone())
        .map_err(|e| format!("Invalid user registration input: {}", e))?;

    let email = &input.email;
    let name = &input.full_name;

    if !email.contains('@') || !email.contains('.') || email.len() < 5 {
        return Err(format!("Invalid email format: {}", email));
    }

    if email.ends_with("@blocked.test") {
        return Err(format!("Email domain is blocked: {}", email));
    }

    let user_id = format!("usr_{}", &Uuid::new_v4().to_string().replace('-', "")[..12]);
    let plan = input.plan.as_deref().unwrap_or("free");
    let source = input.source.as_deref().unwrap_or("web");
    let phone = input.phone.as_deref();

    // Check for existing user (idempotency - simulated)
    if email == "existing@example.com" {
        info!(
            "User {} already exists - returning idempotent success",
            email
        );
        let result = CreateUserAccountResult {
            user_id: "user_existing_001".to_string(),
            email: email.to_string(),
            status: "already_exists".to_string(),
            created_at: "2025-01-01T00:00:00Z".to_string(),
            name: Some(name.to_string()),
            full_name: None,
            phone: None,
            plan: Some(plan.to_string()),
            source: Some(source.to_string()),
            username: None,
            referral_code: None,
            internal_id: None,
            account_status: None,
            email_verified: None,
            verification_token: None,
        };
        return serde_json::to_value(result)
            .map_err(|e| format!("Failed to serialize result: {}", e));
    }

    info!(
        "User account created: {} ({}) on {} plan, user_id={}",
        name, email, plan, user_id
    );

    let result = CreateUserAccountResult {
        user_id,
        email: email.to_string(),
        status: "created".to_string(),
        created_at: chrono::Utc::now().to_rfc3339(),
        name: Some(name.to_string()),
        full_name: Some(name.to_string()),
        phone: phone.map(|s| s.to_string()),
        plan: Some(plan.to_string()),
        source: Some(source.to_string()),
        username: None,
        referral_code: None,
        internal_id: None,
        account_status: Some("created".to_string()),
        email_verified: Some(false),
        verification_token: Some(format!(
            "vrf_{}",
            &Uuid::new_v4().to_string().replace('-', "")[..16]
        )),
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Step 2: Setup Billing Profile (parallel with step 3)
// ============================================================================

/// Sets up the billing profile for the new user based on their plan tier.
#[expect(unused_variables, reason = "context available for future use")]
pub fn setup_billing_profile(
    context: &Value,
    dependency_results: &HashMap<String, Value>,
) -> Result<Value, String> {
    let user: CreateUserAccountResult = dependency_results
        .get("create_user_account")
        .ok_or("Missing create_user_account dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize user result: {}", e))
        })?;

    let plan = user.plan.as_deref().unwrap_or("free");

    let billing_id = format!(
        "bill_{}",
        &Uuid::new_v4().to_string().replace('-', "")[..10]
    );

    let (price, features, billing_required): (f64, Vec<String>, bool) = match plan {
        "enterprise" => (
            299.99,
            vec![
                "basic_features".into(),
                "advanced_analytics".into(),
                "priority_support".into(),
                "custom_integrations".into(),
            ],
            true,
        ),
        "pro" => (
            29.99,
            vec!["basic_features".into(), "advanced_analytics".into()],
            true,
        ),
        _ => (0.0, vec!["basic_features".into()], false),
    };

    let now = chrono::Utc::now();

    if billing_required {
        let next_billing_date = (now + chrono::Duration::days(30)).to_rfc3339();
        let trial_days: i64 = match plan {
            "enterprise" => 30,
            "pro" => 14,
            _ => 0,
        };
        let trial_end = if trial_days > 0 {
            Some((now + chrono::Duration::days(trial_days)).to_rfc3339())
        } else {
            None
        };

        info!(
            "Billing profile created for {}: {} plan at ${:.2}/mo",
            user.user_id, plan, price
        );

        let result = SetupBillingProfileResult {
            billing_id,
            user_id: user.user_id,
            plan: plan.to_string(),
            status: "active".to_string(),
            created_at: now.to_rfc3339(),
            price: Some(price),
            currency: Some("USD".to_string()),
            billing_cycle: Some("monthly".to_string()),
            features: Some(features),
            next_billing_date: Some(next_billing_date),
            trial_end,
            subscription_id: None,
            billing_required: Some(true),
            billing_status: None,
            payment_method_required: Some(true),
            limits: None,
            pricing: None,
            user_internal_id: None,
        };

        serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
    } else {
        info!("Billing skipped for user {} (free plan)", user.user_id);

        let result = SetupBillingProfileResult {
            billing_id,
            user_id: user.user_id,
            plan: plan.to_string(),
            status: "skipped_free_plan".to_string(),
            created_at: now.to_rfc3339(),
            price: Some(0.0),
            currency: None,
            billing_cycle: None,
            features: Some(features),
            next_billing_date: None,
            trial_end: None,
            subscription_id: None,
            billing_required: Some(false),
            billing_status: None,
            payment_method_required: Some(false),
            limits: None,
            pricing: None,
            user_internal_id: None,
        };

        serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
    }
}

// ============================================================================
// Step 3: Initialize Preferences (parallel with step 2)
// ============================================================================

/// Initializes user preferences with plan-appropriate defaults.
pub fn initialize_preferences(
    context: &Value,
    dependency_results: &HashMap<String, Value>,
) -> Result<Value, String> {
    let user: CreateUserAccountResult = dependency_results
        .get("create_user_account")
        .ok_or("Missing create_user_account dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize user result: {}", e))
        })?;

    let plan = user.plan.as_deref().unwrap_or("free");
    let custom_prefs = context.get("preferences");

    // Set plan-specific feature flags
    let (advanced_analytics, api_access, custom_branding, priority_support) = match plan {
        "enterprise" => (true, true, true, true),
        "pro" => (true, true, false, false),
        _ => (false, false, false, false),
    };

    let preferences_id = format!("pref_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);

    let mut default_prefs = match plan {
        "pro" => json!({
            "email_notifications": true,
            "marketing_emails": true,
            "product_updates": true,
            "weekly_digest": true,
            "theme": "dark",
            "language": "en",
            "timezone": "UTC",
            "api_notifications": true
        }),
        "enterprise" => json!({
            "email_notifications": true,
            "marketing_emails": true,
            "product_updates": true,
            "weekly_digest": true,
            "theme": "dark",
            "language": "en",
            "timezone": "UTC",
            "api_notifications": true,
            "audit_logs": true,
            "advanced_reports": true
        }),
        _ => json!({
            "email_notifications": true,
            "marketing_emails": false,
            "product_updates": true,
            "weekly_digest": false,
            "theme": "light",
            "language": "en",
            "timezone": "UTC"
        }),
    };

    let defaults_count = default_prefs.as_object().map(|o| o.len()).unwrap_or(0);

    let custom_count = if let Some(custom_obj) = custom_prefs.and_then(|v| v.as_object()) {
        let prefs_obj = default_prefs.as_object_mut().unwrap();
        for (k, v) in custom_obj {
            prefs_obj.insert(k.clone(), v.clone());
        }
        custom_obj.len()
    } else {
        0
    };

    let now = chrono::Utc::now().to_rfc3339();

    info!(
        "Preferences initialized for {}: {} plan ({} defaults + {} customizations)",
        user.user_id, plan, defaults_count, custom_count
    );

    let result = InitializePreferencesResult {
        preferences_id,
        user_id: user.user_id,
        status: "active".to_string(),
        created_at: now.clone(),
        preferences: Some(default_prefs),
        notifications: None,
        ui_settings: None,
        feature_flags: Some(json!({
            "advanced_analytics": advanced_analytics,
            "api_access": api_access,
            "custom_branding": custom_branding,
            "priority_support": priority_support
        })),
        defaults_applied: Some(defaults_count as i64),
        customizations: Some(custom_count as i64),
        plan: Some(plan.to_string()),
        onboarding_completed: Some(false),
        updated_at: Some(now),
        user_internal_id: None,
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Step 4: Send Welcome Sequence (convergence point)
// ============================================================================

/// Sends a multi-channel welcome sequence to the new user.
#[expect(unused_variables, reason = "context available for future use")]
pub fn send_welcome_sequence(
    context: &Value,
    dependency_results: &HashMap<String, Value>,
) -> Result<Value, String> {
    let user: CreateUserAccountResult = dependency_results
        .get("create_user_account")
        .ok_or("Missing create_user_account dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize user result: {}", e))
        })?;

    let _billing: SetupBillingProfileResult = dependency_results
        .get("setup_billing_profile")
        .ok_or("Missing setup_billing_profile dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize billing result: {}", e))
        })?;

    let preferences: InitializePreferencesResult = dependency_results
        .get("initialize_preferences")
        .ok_or("Missing initialize_preferences dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize preferences result: {}", e))
        })?;

    let plan = user.plan.as_deref().unwrap_or("free");
    let name = user.name.as_deref().unwrap_or("User");

    let email_notifications_enabled = preferences
        .preferences
        .as_ref()
        .and_then(|p| p.get("email_notifications"))
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    let (subject, _greeting) = match plan {
        "pro" => ("Welcome to Pro!", "Thanks for upgrading to Pro"),
        "enterprise" => (
            "Welcome to Enterprise!",
            "Welcome to your Enterprise account",
        ),
        _ => ("Welcome to Our Platform!", "Thanks for joining us"),
    };

    let mut channels_used = Vec::new();
    let mut messages_detail = Vec::new();

    if email_notifications_enabled {
        channels_used.push("email".to_string());
        messages_detail.push(SendWelcomeSequenceResultMessagesSentDetails {
            channel: "email".to_string(),
            template: "welcome_email".to_string(),
            status: "sent".to_string(),
        });
    }

    channels_used.push("in_app".to_string());
    messages_detail.push(SendWelcomeSequenceResultMessagesSentDetails {
        channel: "in_app".to_string(),
        template: "welcome_notification".to_string(),
        status: "delivered".to_string(),
    });

    if plan == "enterprise" {
        channels_used.push("sms".to_string());
        messages_detail.push(SendWelcomeSequenceResultMessagesSentDetails {
            channel: "sms".to_string(),
            template: "enterprise_welcome_sms".to_string(),
            status: "sent".to_string(),
        });
    }

    let sequence_id = format!(
        "welcome_{}",
        &Uuid::new_v4().to_string().replace('-', "")[..12]
    );
    let messages_sent = messages_detail.len() as i64;

    info!(
        "Welcome sequence sent to {} ({}): {} channels",
        name,
        user.email,
        channels_used.len()
    );

    let result = SendWelcomeSequenceResult {
        sequence_id,
        user_id: user.user_id,
        messages_sent,
        status: "sent".to_string(),
        sent_at: chrono::Utc::now().to_rfc3339(),
        channels_used: Some(channels_used),
        messages_sent_details: Some(messages_detail),
        plan: Some(plan.to_string()),
        total_messages: Some(messages_sent),
        welcome_sequence_id: None,
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Step 5: Update User Status
// ============================================================================

/// Activates the user account after all onboarding steps are complete.
pub fn update_user_status(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let user: CreateUserAccountResult = dependency_results
        .get("create_user_account")
        .ok_or("Missing create_user_account dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize user result: {}", e))
        })?;

    let billing: SetupBillingProfileResult = dependency_results
        .get("setup_billing_profile")
        .ok_or("Missing setup_billing_profile dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize billing result: {}", e))
        })?;

    let welcome: SendWelcomeSequenceResult = dependency_results
        .get("send_welcome_sequence")
        .ok_or("Missing send_welcome_sequence dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize welcome result: {}", e))
        })?;

    let plan = user.plan.as_deref().unwrap_or("free");
    let now = chrono::Utc::now().to_rfc3339();

    info!(
        "User {} ({}) activated: plan={}, billing={}",
        user.user_id, user.email, plan, billing.billing_id
    );

    let result = UpdateUserStatusResult {
        user_id: user.user_id.clone(),
        status: "active".to_string(),
        registration_complete: true,
        activated_at: now.clone(),
        plan: Some(plan.to_string()),
        email: Some(user.email.clone()),
        billing_id: Some(billing.billing_id),
        subscription_id: billing.subscription_id,
        welcome_messages_sent: Some(welcome.messages_sent),
        services_completed: Some(vec![
            "user_service".to_string(),
            "billing_service".to_string(),
            "preferences_service".to_string(),
            "notification_service".to_string(),
        ]),
        registration_summary: Some(json!({
            "user_id": user.user_id,
            "email": user.email,
            "plan": plan,
            "registration_status": "complete"
        })),
        all_services_coordinated: Some(true),
        activation_timestamp: Some(now),
        onboarding_status: Some("complete".to_string()),
        account_status: Some("active".to_string()),
        internal_id: None,
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}
