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
pub fn create_user_account(context: &Value) -> Result<Value, String> {
    let email = context.get("user_email")
        .and_then(|v| v.as_str())
        .ok_or("Missing user_email in context")?;

    let name = context.get("user_name")
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown User");

    // Validate email format (basic check)
    if !email.contains('@') || !email.contains('.') {
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

    // Determine initial quota based on plan
    let (storage_gb, api_calls_per_month) = match plan {
        "enterprise" => (1000, 1_000_000),
        "pro" => (100, 100_000),
        _ => (5, 1_000),
    };

    info!(
        "User account created: {} ({}) on {} plan, user_id={}",
        name, email, plan, user_id
    );

    Ok(json!({
        "user_id": user_id,
        "account_number": account_number,
        "email": email,
        "name": name,
        "plan": plan,
        "initial_quotas": {
            "storage_gb": storage_gb,
            "api_calls_per_month": api_calls_per_month
        },
        "status": "created",
        "created_at": chrono::Utc::now().to_rfc3339()
    }))
}

// ============================================================================
// Step 2: Setup Billing Profile (parallel with step 3)
// ============================================================================

/// Sets up the billing profile for the new user based on their plan tier.
/// Configures payment method placeholders, billing cycle, and trial periods.
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

    // Configure billing based on plan
    let (monthly_cost, trial_days, billing_cycle) = match plan {
        "enterprise" => (299.99, 30, "annual"),
        "pro" => (49.99, 14, "monthly"),
        _ => (0.0, 0, "none"),
    };

    let trial_end = if trial_days > 0 {
        Some((chrono::Utc::now() + chrono::Duration::days(trial_days)).to_rfc3339())
    } else {
        None
    };

    info!(
        "Billing profile created for {}: {} plan at ${:.2}/mo (trial: {} days)",
        user_id, plan, monthly_cost, trial_days
    );

    Ok(json!({
        "billing_id": billing_id,
        "user_id": user_id,
        "plan": plan,
        "monthly_cost": monthly_cost,
        "billing_cycle": billing_cycle,
        "trial_period_days": trial_days,
        "trial_end_date": trial_end,
        "payment_method": "pending_setup",
        "currency": "USD",
        "status": "active",
        "created_at": chrono::Utc::now().to_rfc3339()
    }))
}

// ============================================================================
// Step 3: Initialize Preferences (parallel with step 2)
// ============================================================================

/// Initializes user preferences with plan-appropriate defaults.
/// Sets notification preferences, dashboard layout, and feature flags.
pub fn initialize_preferences(context: &Value, dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let user_result = dependency_results.get("create_user_account")
        .ok_or("Missing create_user_account dependency")?;

    let user_id = user_result.get("user_id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let plan = user_result.get("plan")
        .and_then(|v| v.as_str())
        .unwrap_or("free");

    // Set plan-specific feature flags
    let (advanced_analytics, api_access, custom_branding, priority_support) = match plan {
        "enterprise" => (true, true, true, true),
        "pro" => (true, true, false, false),
        _ => (false, false, false, false),
    };

    let preferences_id = format!("pref_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);

    // Set default notification preferences
    let notifications = json!({
        "email_digest": "weekly",
        "push_notifications": true,
        "sms_alerts": plan == "enterprise",
        "marketing_emails": false,
        "security_alerts": true,
        "billing_notifications": true
    });

    // Set default dashboard layout
    let dashboard = json!({
        "theme": "system",
        "language": "en",
        "timezone": "UTC",
        "date_format": "YYYY-MM-DD",
        "compact_view": false
    });

    info!(
        "Preferences initialized for {}: {} plan (analytics={}, api={})",
        user_id, plan, advanced_analytics, api_access
    );

    Ok(json!({
        "preferences_id": preferences_id,
        "user_id": user_id,
        "notifications": notifications,
        "dashboard": dashboard,
        "feature_flags": {
            "advanced_analytics": advanced_analytics,
            "api_access": api_access,
            "custom_branding": custom_branding,
            "priority_support": priority_support
        },
        "status": "configured",
        "created_at": chrono::Utc::now().to_rfc3339()
    }))
}

// ============================================================================
// Step 4: Send Welcome Sequence (convergence point)
// ============================================================================

/// Sends a multi-channel welcome sequence to the new user.
/// Dispatches welcome email, in-app notification, and optional SMS.
pub fn send_welcome_sequence(context: &Value, dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let user_result = dependency_results.get("create_user_account")
        .ok_or("Missing create_user_account dependency")?;

    let billing_result = dependency_results.get("setup_billing_profile")
        .ok_or("Missing setup_billing_profile dependency")?;

    let preferences_result = dependency_results.get("initialize_preferences")
        .ok_or("Missing initialize_preferences dependency")?;

    let user_id = user_result.get("user_id").and_then(|v| v.as_str()).unwrap_or("unknown");
    let email = user_result.get("email").and_then(|v| v.as_str()).unwrap_or("unknown@example.com");
    let name = user_result.get("name").and_then(|v| v.as_str()).unwrap_or("User");
    let plan = user_result.get("plan").and_then(|v| v.as_str()).unwrap_or("free");
    let trial_days = billing_result.get("trial_period_days").and_then(|v| v.as_i64()).unwrap_or(0);
    let has_sms = preferences_result
        .get("notifications")
        .and_then(|n| n.get("sms_alerts"))
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let mut messages_sent = Vec::new();

    // Welcome email
    let email_id = format!("msg_email_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);
    messages_sent.push(json!({
        "message_id": email_id,
        "channel": "email",
        "recipient": email,
        "template": "welcome_email_v2",
        "subject": format!("Welcome to the platform, {}!", name),
        "status": "sent"
    }));

    // In-app notification
    let notif_id = format!("msg_inapp_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);
    messages_sent.push(json!({
        "message_id": notif_id,
        "channel": "in_app",
        "recipient": user_id,
        "template": "welcome_notification",
        "content": format!("Welcome aboard, {}! Get started with our quick setup guide.", name),
        "status": "delivered"
    }));

    // Conditional SMS for enterprise users
    if has_sms {
        let sms_id = format!("msg_sms_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);
        messages_sent.push(json!({
            "message_id": sms_id,
            "channel": "sms",
            "template": "welcome_sms",
            "content": format!("Welcome {}! Your enterprise account is ready. Check your email for next steps.", name),
            "status": "sent"
        }));
    }

    // Trial reminder if applicable
    if trial_days > 0 {
        let reminder_id = format!("msg_sched_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);
        messages_sent.push(json!({
            "message_id": reminder_id,
            "channel": "scheduled_email",
            "recipient": email,
            "template": "trial_reminder",
            "scheduled_for": (chrono::Utc::now() + chrono::Duration::days(trial_days - 3)).to_rfc3339(),
            "status": "scheduled"
        }));
    }

    info!(
        "Welcome sequence sent to {} ({}): {} messages across {} channels",
        name, email, messages_sent.len(),
        messages_sent.iter().map(|m| m["channel"].as_str().unwrap_or("")).collect::<Vec<_>>().join(", ")
    );

    Ok(json!({
        "user_id": user_id,
        "messages_sent": messages_sent,
        "total_messages": messages_sent.len(),
        "plan": plan,
        "status": "completed",
        "sent_at": chrono::Utc::now().to_rfc3339()
    }))
}

// ============================================================================
// Step 5: Update User Status
// ============================================================================

/// Activates the user account after all onboarding steps are complete.
/// Aggregates results from all prior steps to set final account state.
pub fn update_user_status(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let user_result = dependency_results.get("create_user_account")
        .ok_or("Missing create_user_account dependency")?;

    let billing_result = dependency_results.get("setup_billing_profile")
        .ok_or("Missing setup_billing_profile dependency")?;

    let welcome_result = dependency_results.get("send_welcome_sequence")
        .ok_or("Missing send_welcome_sequence dependency")?;

    let user_id = user_result.get("user_id").and_then(|v| v.as_str()).unwrap_or("unknown");
    let email = user_result.get("email").and_then(|v| v.as_str()).unwrap_or("unknown");
    let plan = user_result.get("plan").and_then(|v| v.as_str()).unwrap_or("free");
    let billing_id = billing_result.get("billing_id").and_then(|v| v.as_str()).unwrap_or("unknown");
    let messages_count = welcome_result.get("total_messages").and_then(|v| v.as_i64()).unwrap_or(0);

    info!(
        "User {} ({}) activated: plan={}, billing={}, welcome_messages={}",
        user_id, email, plan, billing_id, messages_count
    );

    Ok(json!({
        "user_id": user_id,
        "email": email,
        "plan": plan,
        "status": "active",
        "onboarding_complete": true,
        "billing_id": billing_id,
        "welcome_messages_sent": messages_count,
        "activated_at": chrono::Utc::now().to_rfc3339(),
        "next_review_date": (chrono::Utc::now() + chrono::Duration::days(30)).to_rfc3339()
    }))
}
