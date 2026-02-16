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

use serde_json::{json, Value};
use std::collections::HashMap;
use tracing::info;
use uuid::Uuid;

// ============================================================================
// Step 1: Create User Account
// ============================================================================

/// Validates the user email, checks for duplicates, and creates a new user account.
/// Generates a unique user ID and sets initial account state.
///
/// Context keys (flat): email, full_name, plan, phone, source
pub fn create_user_account(context: &Value) -> Result<Value, String> {
    // Route sends flat fields: email, full_name, plan, phone, source
    let email = context.get("email")
        .and_then(|v| v.as_str())
        .ok_or("Missing email in context")?;

    let name = context.get("full_name")
        .and_then(|v| v.as_str())
        .ok_or("Missing full_name in context")?;

    // Validate email format (basic check)
    if !email.contains('@') || !email.contains('.') || email.len() < 5 {
        return Err(format!("Invalid email format: {}", email));
    }

    // Check for test blocked emails
    if email.ends_with("@blocked.test") {
        return Err(format!("Email domain is blocked: {}", email));
    }

    let user_id = format!("usr_{}", &Uuid::new_v4().to_string().replace('-', "")[..12]);
    let account_number = format!("ACC-{}", &Uuid::new_v4().to_string().replace('-', "")[..8].to_uppercase());
    let plan = context.get("plan")
        .and_then(|v| v.as_str())
        .unwrap_or("free");
    let source = context.get("source")
        .and_then(|v| v.as_str())
        .unwrap_or("web");

    // Determine initial quota based on plan
    let (storage_gb, api_calls_per_month) = match plan {
        "enterprise" => (1000, 1_000_000),
        "pro" => (100, 100_000),
        _ => (5, 1_000),
    };

    // Check for existing user (idempotency - simulated)
    if email == "existing@example.com" {
        info!("User {} already exists - returning idempotent success", email);
        return Ok(json!({
            "user_id": "user_existing_001",
            "email": email,
            "plan": plan,
            "status": "already_exists",
            "created_at": "2025-01-01T00:00:00Z"
        }));
    }

    info!(
        "User account created: {} ({}) on {} plan, user_id={}",
        name, email, plan, user_id
    );

    // Output keys aligned with source: user_id, email, name, plan, source, status, created_at
    let mut result = json!({
        "user_id": user_id,
        "account_number": account_number,
        "email": email,
        "name": name,
        "plan": plan,
        "source": source,
        "initial_quotas": {
            "storage_gb": storage_gb,
            "api_calls_per_month": api_calls_per_month
        },
        "status": "created",
        "created_at": chrono::Utc::now().to_rfc3339()
    });

    // Include phone if provided (matches source behavior)
    if let Some(phone) = context.get("phone").and_then(|v| v.as_str()) {
        result["phone"] = json!(phone);
    }

    Ok(result)
}

// ============================================================================
// Step 2: Setup Billing Profile (parallel with step 3)
// ============================================================================

/// Sets up the billing profile for the new user based on their plan tier.
/// Configures payment method placeholders, billing cycle, and trial periods.
///
/// Dependency reads (aligned with source): create_user_account -> user_id, plan
/// Output keys (aligned with source): billing_id, user_id, plan, price, currency, billing_cycle,
///   features, status, next_billing_date, created_at (paid) OR user_id, plan, billing_required,
///   status, message (free)
pub fn setup_billing_profile(context: &Value, dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let user_result = dependency_results.get("create_user_account")
        .ok_or("Missing create_user_account dependency")?;

    let user_id = user_result.get("user_id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let plan = user_result.get("plan")
        .and_then(|v| v.as_str())
        .unwrap_or("free");

    let billing_id = format!("bill_{}", &Uuid::new_v4().to_string().replace('-', "")[..10]);

    // Configure billing based on plan (source uses get_billing_tier)
    let (price, features, billing_required): (f64, Vec<&str>, bool) = match plan {
        "enterprise" => (299.99, vec!["basic_features", "advanced_analytics", "priority_support", "custom_integrations"], true),
        "pro" => (29.99, vec!["basic_features", "advanced_analytics"], true),
        _ => (0.0, vec!["basic_features"], false),
    };

    if billing_required {
        // Paid plan - create billing profile
        let now = chrono::Utc::now();
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
            user_id, plan, price
        );

        // Output keys aligned with source: billing_id, user_id, plan, price, currency,
        // billing_cycle, features, status, next_billing_date, created_at
        Ok(json!({
            "billing_id": billing_id,
            "user_id": user_id,
            "plan": plan,
            "price": price,
            "currency": "USD",
            "billing_cycle": "monthly",
            "features": features,
            "status": "active",
            "next_billing_date": next_billing_date,
            "trial_period_days": trial_days,
            "trial_end_date": trial_end,
            "payment_method": "pending_setup",
            "created_at": now.to_rfc3339()
        }))
    } else {
        // Free plan - graceful degradation (matches source free plan path)
        info!("Billing skipped for user {} (free plan)", user_id);

        Ok(json!({
            "billing_id": billing_id,
            "user_id": user_id,
            "plan": plan,
            "billing_required": false,
            "status": "skipped_free_plan",
            "message": "Free plan users do not require billing setup"
        }))
    }
}

// ============================================================================
// Step 3: Initialize Preferences (parallel with step 2)
// ============================================================================

/// Initializes user preferences with plan-appropriate defaults.
/// Sets notification preferences, dashboard layout, and feature flags.
///
/// Dependency reads (aligned with source): create_user_account -> user_id, plan
/// Context reads (aligned with source): user_info -> preferences (optional)
/// Output keys (aligned with source): preferences_id, user_id, plan, preferences,
///   defaults_applied, customizations, status, created_at, updated_at
pub fn initialize_preferences(context: &Value, dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let user_result = dependency_results.get("create_user_account")
        .ok_or("Missing create_user_account dependency")?;

    let user_id = user_result.get("user_id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let plan = user_result.get("plan")
        .and_then(|v| v.as_str())
        .unwrap_or("free");

    // Route sends flat field: preferences (optional)
    let custom_prefs = context.get("preferences");

    // Set plan-specific feature flags
    let (advanced_analytics, api_access, custom_branding, priority_support) = match plan {
        "enterprise" => (true, true, true, true),
        "pro" => (true, true, false, false),
        _ => (false, false, false, false),
    };

    let preferences_id = format!("pref_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);

    // Build default preferences based on plan (aligned with source get_default_preferences)
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

    // Merge custom preferences if provided
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
        "Preferences initialized for {}: {} plan (analytics={}, api={}, {} defaults + {} customizations)",
        user_id, plan, advanced_analytics, api_access, defaults_count, custom_count
    );

    // Output keys aligned with source: preferences_id, user_id, plan, preferences,
    // defaults_applied, customizations, status, created_at, updated_at
    Ok(json!({
        "preferences_id": preferences_id,
        "user_id": user_id,
        "plan": plan,
        "preferences": default_prefs,
        "defaults_applied": defaults_count,
        "customizations": custom_count,
        "feature_flags": {
            "advanced_analytics": advanced_analytics,
            "api_access": api_access,
            "custom_branding": custom_branding,
            "priority_support": priority_support
        },
        "status": "active",
        "created_at": now,
        "updated_at": now
    }))
}

// ============================================================================
// Step 4: Send Welcome Sequence (convergence point)
// ============================================================================

/// Sends a multi-channel welcome sequence to the new user.
/// Dispatches welcome email, in-app notification, and optional SMS.
///
/// Dependency reads (aligned with source):
///   create_user_account -> user_id, email, plan
///   setup_billing_profile -> billing_id
///   initialize_preferences -> preferences.email_notifications
/// Output keys (aligned with source): user_id, plan, channels_used, messages_sent (count),
///   welcome_sequence_id, status, sent_at, highlights, upgrade_prompt, billing_id
pub fn send_welcome_sequence(context: &Value, dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let user_result = dependency_results.get("create_user_account")
        .ok_or("Missing create_user_account dependency")?;

    let billing_result = dependency_results.get("setup_billing_profile")
        .ok_or("Missing setup_billing_profile dependency")?;

    let preferences_result = dependency_results.get("initialize_preferences")
        .ok_or("Missing initialize_preferences dependency")?;

    // Source reads: user_id, email, plan from create_user_account
    let user_id = user_result.get("user_id").and_then(|v| v.as_str()).unwrap_or("unknown");
    let email = user_result.get("email").and_then(|v| v.as_str()).unwrap_or("unknown@example.com");
    let name = user_result.get("name").and_then(|v| v.as_str()).unwrap_or("User");
    let plan = user_result.get("plan").and_then(|v| v.as_str()).unwrap_or("free");

    // Source reads: billing_id from setup_billing_profile (optional for free plans)
    let billing_id = billing_result.get("billing_id").and_then(|v| v.as_str());

    // Source reads: preferences.email_notifications from initialize_preferences
    let email_notifications_enabled = preferences_result
        .get("preferences")
        .and_then(|p| p.get("email_notifications"))
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    let has_sms = preferences_result
        .get("preferences")
        .and_then(|p| p.get("api_notifications"))
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    // Generate welcome template based on plan (aligned with source get_welcome_template)
    let (subject, greeting, highlights, upgrade_prompt): (String, String, Vec<String>, Option<String>) = match plan {
        "pro" => (
            "Welcome to Pro!".to_string(),
            "Thanks for upgrading to Pro".to_string(),
            vec![
                "Access advanced analytics".to_string(),
                "Priority support".to_string(),
                "API access".to_string(),
                "Custom integrations".to_string(),
            ],
            Some("Consider Enterprise for dedicated support".to_string()),
        ),
        "enterprise" => (
            "Welcome to Enterprise!".to_string(),
            "Welcome to your Enterprise account".to_string(),
            vec![
                "Dedicated account manager".to_string(),
                "Custom SLA".to_string(),
                "Advanced security features".to_string(),
                "Priority support 24/7".to_string(),
            ],
            None,
        ),
        _ => (
            "Welcome to Our Platform!".to_string(),
            "Thanks for joining us".to_string(),
            vec![
                "Get started with basic features".to_string(),
                "Explore your dashboard".to_string(),
                "Join our community".to_string(),
            ],
            Some("Upgrade to Pro for advanced features".to_string()),
        ),
    };

    let mut channels_used = Vec::new();
    let mut messages_detail = Vec::new();
    let now = chrono::Utc::now().to_rfc3339();

    // Email (if notifications enabled - source checks email_notifications)
    if email_notifications_enabled {
        channels_used.push("email".to_string());
        let email_id = format!("msg_email_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);
        messages_detail.push(json!({
            "message_id": email_id,
            "channel": "email",
            "recipient": email,
            "subject": subject,
            "status": "sent"
        }));
    }

    // In-app notification (always)
    channels_used.push("in_app".to_string());
    let notif_id = format!("msg_inapp_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);
    messages_detail.push(json!({
        "message_id": notif_id,
        "channel": "in_app",
        "user_id": user_id,
        "title": subject,
        "message": greeting,
        "status": "delivered"
    }));

    // SMS (enterprise only - source checks plan == "enterprise")
    if plan == "enterprise" {
        channels_used.push("sms".to_string());
        let sms_id = format!("msg_sms_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);
        messages_detail.push(json!({
            "message_id": sms_id,
            "channel": "sms",
            "message": "Welcome to Enterprise! Your account manager will contact you soon.",
            "status": "sent"
        }));
    }

    let welcome_sequence_id = format!("welcome_{}", &Uuid::new_v4().to_string().replace('-', "")[..12]);

    info!(
        "Welcome sequence sent to {} ({}): {} channels",
        name, email, channels_used.len()
    );

    // Output keys aligned with source: user_id, plan, channels_used, messages_sent (count),
    // welcome_sequence_id, status, sent_at, highlights, upgrade_prompt, billing_id
    Ok(json!({
        "user_id": user_id,
        "plan": plan,
        "channels_used": channels_used,
        "messages_sent": messages_detail.len(),
        "welcome_sequence_id": welcome_sequence_id,
        "status": "sent",
        "sent_at": now,
        "highlights": highlights,
        "upgrade_prompt": upgrade_prompt,
        "billing_id": billing_id,
        "messages_detail": messages_detail
    }))
}

// ============================================================================
// Step 5: Update User Status
// ============================================================================

/// Activates the user account after all onboarding steps are complete.
/// Aggregates results from all prior steps to set final account state.
///
/// Dependency reads (aligned with source):
///   create_user_account -> user_id, email, plan, created_at
///   setup_billing_profile -> billing_id, next_billing_date
///   initialize_preferences -> preferences
///   send_welcome_sequence -> channels_used
/// Output keys (aligned with source): user_id, status, plan, registration_summary,
///   activation_timestamp, all_services_coordinated, services_completed
pub fn update_user_status(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let user_result = dependency_results.get("create_user_account")
        .ok_or("Missing create_user_account dependency")?;

    let billing_result = dependency_results.get("setup_billing_profile")
        .ok_or("Missing setup_billing_profile dependency")?;

    let prefs_result = dependency_results.get("initialize_preferences")
        .ok_or("Missing initialize_preferences dependency")?;

    let welcome_result = dependency_results.get("send_welcome_sequence")
        .ok_or("Missing send_welcome_sequence dependency")?;

    // Source reads: user_id, email, plan, created_at from create_user_account
    let user_id = user_result.get("user_id").and_then(|v| v.as_str()).unwrap_or("unknown");
    let email = user_result.get("email").and_then(|v| v.as_str()).unwrap_or("unknown");
    let plan = user_result.get("plan").and_then(|v| v.as_str()).unwrap_or("free");
    let user_created_at = user_result.get("created_at").and_then(|v| v.as_str());

    // Source reads: billing_id, next_billing_date from setup_billing_profile
    let billing_id = billing_result.get("billing_id").and_then(|v| v.as_str());
    let next_billing_date = billing_result.get("next_billing_date").and_then(|v| v.as_str());

    // Source reads: preferences from initialize_preferences
    let prefs_count = prefs_result.get("preferences")
        .and_then(|p| p.as_object())
        .map(|o| o.len())
        .unwrap_or(0);

    // Source reads: channels_used from send_welcome_sequence
    let notification_channels = welcome_result.get("channels_used")
        .cloned()
        .unwrap_or(json!([]));

    // Build registration summary (aligned with source)
    let mut summary = json!({
        "user_id": user_id,
        "email": email,
        "plan": plan,
        "registration_status": "complete"
    });

    if plan != "free" {
        if let Some(bid) = billing_id {
            summary["billing_id"] = json!(bid);
        }
        if let Some(nbd) = next_billing_date {
            summary["next_billing_date"] = json!(nbd);
        }
    }

    summary["preferences_count"] = json!(prefs_count);
    summary["welcome_sent"] = json!(true);
    summary["notification_channels"] = notification_channels.clone();

    if let Some(created) = user_created_at {
        summary["user_created_at"] = json!(created);
    }

    let now = chrono::Utc::now().to_rfc3339();
    summary["registration_completed_at"] = json!(&now);

    info!(
        "User {} ({}) activated: plan={}, billing={:?}, welcome_channels={:?}",
        user_id, email, plan, billing_id, notification_channels
    );

    // Output keys aligned with source: user_id, status, plan, registration_summary,
    // activation_timestamp, all_services_coordinated, services_completed
    Ok(json!({
        "user_id": user_id,
        "status": "active",
        "plan": plan,
        "registration_summary": summary,
        "activation_timestamp": now,
        "all_services_coordinated": true,
        "services_completed": [
            "user_service",
            "billing_service",
            "preferences_service",
            "notification_service"
        ],
        "email": email,
        "onboarding_complete": true,
        "next_review_date": (chrono::Utc::now() + chrono::Duration::days(30)).to_rfc3339()
    }))
}
