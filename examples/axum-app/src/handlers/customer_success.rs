//! # Customer Success Refund Processing Handlers
//!
//! Handlers for the Customer Success namespace in the team scaling workflow.
//! Demonstrates namespace isolation where a customer success team handles
//! the front-end refund process.
//!
//! ## Steps (5)
//!
//! 1. **team_scaling_cs_validate_refund_request**: Validate refund request data
//! 2. **team_scaling_cs_check_refund_policy**: Check against refund policies
//! 3. **team_scaling_cs_get_manager_approval**: Conditional manager approval
//! 4. **team_scaling_cs_execute_refund_workflow**: Coordinate the refund execution
//! 5. **team_scaling_cs_update_ticket_status**: Update the support ticket

use serde_json::{json, Value};
use std::collections::HashMap;
use tracing::info;
use uuid::Uuid;

// ============================================================================
// Helper Functions
// ============================================================================

/// Determine customer tier based on customer ID (aligned with source)
fn determine_customer_tier(customer_id: &str) -> &'static str {
    let lower = customer_id.to_lowercase();
    if lower.contains("vip") || lower.contains("premium") {
        "premium"
    } else if lower.contains("gold") {
        "gold"
    } else {
        "standard"
    }
}

/// Refund policy rules by tier (aligned with source)
fn get_refund_policy(tier: &str) -> (i32, bool, i64) {
    // (window_days, requires_approval, max_amount)
    match tier {
        "gold" => (60, false, 50_000),
        "premium" => (90, false, 100_000),
        _ => (30, true, 10_000), // standard
    }
}

// ============================================================================
// Step 1: Validate Refund Request
// ============================================================================

/// Validates the incoming refund request, checking for required fields,
/// valid amounts, and order existence. Enriches the request with order details.
///
/// Context keys (aligned with source): ticket_id, customer_id, refund_amount
/// Output keys (aligned with source): request_validated, ticket_id, customer_id,
///   ticket_status, customer_tier, original_purchase_date, payment_id,
///   validation_timestamp, namespace
pub fn validate_refund_request(context: &Value) -> Result<Value, String> {
    // Source reads: ticket_id, customer_id, refund_amount from task context
    let ticket_id = context.get("ticket_id")
        .and_then(|v| v.as_str())
        .ok_or("Missing ticket_id in context")?;

    let customer_id = context.get("customer_id")
        .and_then(|v| v.as_str())
        .ok_or("Missing customer_id in context")?;

    let refund_amount = context.get("refund_amount")
        .and_then(|v| v.as_f64())
        .ok_or("Missing or invalid refund_amount in context")?;

    // Also read app-specific fields that may be in context
    let customer_email = context.get("customer_email")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown@example.com");

    let order_id = context.get("order_id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let reason = context.get("reason")
        .and_then(|v| v.as_str())
        .unwrap_or("No reason provided");

    // Validate amount range
    if refund_amount <= 0.0 {
        return Err("Refund amount must be positive".to_string());
    }
    if refund_amount > 10000.0 {
        return Err(format!("Refund amount ${:.2} exceeds maximum single refund limit of $10,000", refund_amount));
    }

    // Simulate ticket validation scenarios (aligned with source)
    if ticket_id.contains("ticket_closed") {
        return Err("Cannot process refund for closed ticket".to_string());
    }
    if ticket_id.contains("ticket_cancelled") {
        return Err("Cannot process refund for cancelled ticket".to_string());
    }

    let customer_tier = determine_customer_tier(customer_id);
    let purchase_date = (chrono::Utc::now() - chrono::Duration::days(30)).to_rfc3339();
    let payment_id = format!("pay_{}", &Uuid::new_v4().to_string().replace('-', "")[..12]);
    let now = chrono::Utc::now().to_rfc3339();

    info!(
        "Refund request validated: ticket={}, customer_id={}, customer_tier={}, amount=${:.2}",
        ticket_id, customer_id, customer_tier, refund_amount
    );

    // Output keys aligned with source: request_validated, ticket_id, customer_id,
    // ticket_status, customer_tier, original_purchase_date, payment_id,
    // validation_timestamp, namespace
    Ok(json!({
        "request_validated": true,
        "ticket_id": ticket_id,
        "customer_id": customer_id,
        "ticket_status": "open",
        "customer_tier": customer_tier,
        "original_purchase_date": purchase_date,
        "payment_id": payment_id,
        "validation_timestamp": now,
        "namespace": "customer_success_rs",
        "customer_email": customer_email,
        "order_id": order_id,
        "refund_amount": refund_amount,
        "reason": reason
    }))
}

// ============================================================================
// Step 2: Check Refund Policy
// ============================================================================

/// Evaluates the refund request against company refund policies.
/// Determines if the refund requires manager approval based on amount and timing.
///
/// Dependency reads (aligned with source):
///   validate_refund_request -> full result (request_validated), customer_tier
/// Context reads (aligned with source): refund_amount
/// Output keys (aligned with source): policy_checked, policy_compliant, customer_tier,
///   refund_window_days, days_since_purchase, within_refund_window, requires_approval,
///   max_allowed_amount, policy_checked_at, namespace
pub fn check_refund_policy(context: &Value, dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let validation = dependency_results.get("validate_refund_request")
        .ok_or("Missing validate_refund_request dependency")?;

    // Source checks request_validated from dependency result
    let validated = validation.get("request_validated")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    if !validated {
        return Err("Request validation must be completed before policy check".to_string());
    }

    // Source reads: customer_tier from validate_refund_request
    let customer_tier = validation.get("customer_tier")
        .and_then(|v| v.as_str())
        .unwrap_or("standard");

    // Source reads: refund_amount from task context
    let refund_amount = context.get("refund_amount")
        .and_then(|v| v.as_f64())
        .or_else(|| validation.get("refund_amount").and_then(|v| v.as_f64()))
        .unwrap_or(0.0);

    // Check policy compliance (aligned with source get_refund_policy)
    let (window_days, requires_approval, max_amount) = get_refund_policy(customer_tier);
    let days_since_purchase = 30; // Simplified for demo
    let within_window = days_since_purchase <= window_days;
    let within_amount_limit = (refund_amount as i64) <= max_amount;

    if !within_window {
        return Err(format!(
            "Refund request outside policy window: {} days (max: {} days)",
            days_since_purchase, window_days
        ));
    }

    if !within_amount_limit {
        return Err(format!(
            "Refund amount exceeds policy limit: ${:.2} (max: ${:.2})",
            refund_amount / 100.0,
            max_amount as f64 / 100.0
        ));
    }

    let now = chrono::Utc::now().to_rfc3339();

    info!(
        "Policy check passed: customer_tier={}, requires_approval={}, refund_amount=${:.2}",
        customer_tier, requires_approval, refund_amount
    );

    // Output keys aligned with source: policy_checked, policy_compliant, customer_tier,
    // refund_window_days, days_since_purchase, within_refund_window, requires_approval,
    // max_allowed_amount, policy_checked_at, namespace
    Ok(json!({
        "policy_checked": true,
        "policy_compliant": true,
        "customer_tier": customer_tier,
        "refund_window_days": window_days,
        "days_since_purchase": days_since_purchase,
        "within_refund_window": within_window,
        "requires_approval": requires_approval,
        "max_allowed_amount": max_amount,
        "policy_checked_at": now,
        "namespace": "customer_success_rs"
    }))
}

// ============================================================================
// Step 3: Get Manager Approval
// ============================================================================

/// Routes the refund for manager approval if policies require it.
/// For refunds that pass all policies, auto-approval is granted.
///
/// Dependency reads (aligned with source):
///   check_refund_policy -> full result (policy_checked), requires_approval, customer_tier
///   validate_refund_request -> ticket_id, customer_id
/// Output keys (aligned with source): approval_obtained, approval_required, auto_approved,
///   approval_id, manager_id, manager_notes, approved_at, namespace
pub fn get_manager_approval(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let policy_result = dependency_results.get("check_refund_policy")
        .ok_or("Missing check_refund_policy dependency")?;

    let validation = dependency_results.get("validate_refund_request")
        .ok_or("Missing validate_refund_request dependency")?;

    // Source checks policy_checked from dependency result
    let policy_checked = policy_result.get("policy_checked")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    if !policy_checked {
        return Err("Policy check must be completed before approval".to_string());
    }

    // Source reads: requires_approval, customer_tier from check_refund_policy
    let requires_approval = policy_result.get("requires_approval")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    let customer_tier = policy_result.get("customer_tier")
        .and_then(|v| v.as_str())
        .unwrap_or("standard");

    // Source reads: ticket_id, customer_id from validate_refund_request
    let ticket_id = validation.get("ticket_id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let customer_id = validation.get("customer_id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let now = chrono::Utc::now().to_rfc3339();

    if requires_approval {
        // Simulate approval scenarios (aligned with source)
        if ticket_id.contains("ticket_denied") {
            return Err("Manager denied refund request".to_string());
        }
        if ticket_id.contains("ticket_pending") {
            return Err("Waiting for manager approval (retryable)".to_string());
        }

        let approval_id = format!("appr_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);
        let manager_id = format!("mgr_{}", (ticket_id.len() % 5) + 1);

        info!(
            "Manager approval obtained: approval_id={}, manager_id={}",
            approval_id, manager_id
        );

        // Output keys aligned with source: approval_obtained, approval_required, auto_approved,
        // approval_id, manager_id, manager_notes, approved_at, namespace
        Ok(json!({
            "approval_obtained": true,
            "approval_required": true,
            "auto_approved": false,
            "approval_id": approval_id,
            "manager_id": manager_id,
            "manager_notes": format!("Approved refund request for customer {}", customer_id),
            "approved_at": now,
            "namespace": "customer_success_rs"
        }))
    } else {
        info!(
            "Auto-approved for tier={}, ticket={}",
            customer_tier, ticket_id
        );

        Ok(json!({
            "approval_obtained": true,
            "approval_required": false,
            "auto_approved": true,
            "approval_id": null,
            "manager_id": null,
            "manager_notes": format!("Auto-approved for customer tier {}", customer_tier),
            "approved_at": now,
            "namespace": "customer_success_rs"
        }))
    }
}

// ============================================================================
// Step 4: Execute Refund Workflow
// ============================================================================

/// Coordinates the actual refund execution by gathering all approvals
/// and creating the refund execution record.
///
/// Dependency reads (aligned with source):
///   get_manager_approval -> full result (approval_obtained)
///   validate_refund_request -> payment_id
/// Output keys (aligned with source): task_delegated, target_namespace, target_workflow,
///   delegated_task_id, delegated_task_status, delegation_timestamp, correlation_id, namespace
pub fn execute_refund_workflow(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let approval = dependency_results.get("get_manager_approval")
        .ok_or("Missing get_manager_approval dependency")?;

    let validation = dependency_results.get("validate_refund_request")
        .ok_or("Missing validate_refund_request dependency")?;

    // Source checks approval_obtained from dependency result
    let approval_obtained = approval.get("approval_obtained")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    if !approval_obtained {
        return Err("Manager approval must be obtained before executing refund".to_string());
    }

    // Source reads: payment_id from validate_refund_request
    let payment_id = validation.get("payment_id")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    if payment_id.is_empty() {
        return Err("Payment ID not found in validation results".to_string());
    }

    let ticket_id = validation.get("ticket_id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let correlation_id = format!("cs-corr_{}", &Uuid::new_v4().to_string().replace('-', "")[..12]);
    let task_id = format!("task_{}", Uuid::new_v4());
    let now = chrono::Utc::now().to_rfc3339();

    info!(
        "Refund workflow delegated: task_id={}, correlation_id={}, ticket={}",
        task_id, correlation_id, ticket_id
    );

    // Output keys aligned with source: task_delegated, target_namespace, target_workflow,
    // delegated_task_id, delegated_task_status, delegation_timestamp, correlation_id, namespace
    Ok(json!({
        "task_delegated": true,
        "target_namespace": "payments_rs",
        "target_workflow": "process_refund",
        "delegated_task_id": task_id,
        "delegated_task_status": "created",
        "delegation_timestamp": now,
        "correlation_id": correlation_id,
        "namespace": "customer_success_rs"
    }))
}

// ============================================================================
// Step 5: Update Ticket Status
// ============================================================================

/// Updates the support ticket with the final refund outcome.
/// Records the complete refund timeline for audit purposes.
///
/// Dependency reads (aligned with source):
///   execute_refund_workflow -> full result (task_delegated), delegated_task_id, correlation_id
///   validate_refund_request -> ticket_id
/// Context reads (aligned with source): refund_amount
/// Output keys (aligned with source): ticket_updated, ticket_id, previous_status, new_status,
///   resolution_note, updated_at, refund_completed, delegated_task_id, namespace
pub fn update_ticket_status(context: &Value, dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let execution = dependency_results.get("execute_refund_workflow")
        .ok_or("Missing execute_refund_workflow dependency")?;

    let validation = dependency_results.get("validate_refund_request")
        .ok_or("Missing validate_refund_request dependency")?;

    // Source checks task_delegated from dependency result
    let task_delegated = execution.get("task_delegated")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    if !task_delegated {
        return Err("Refund workflow must be executed before updating ticket".to_string());
    }

    // Source reads: ticket_id from validate_refund_request
    let ticket_id = validation.get("ticket_id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    // Source reads: delegated_task_id, correlation_id from execute_refund_workflow
    let delegated_task_id = execution.get("delegated_task_id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let correlation_id = execution.get("correlation_id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    // Source reads: refund_amount from task context
    let refund_amount = context.get("refund_amount")
        .and_then(|v| v.as_f64())
        .or_else(|| validation.get("refund_amount").and_then(|v| v.as_f64()))
        .unwrap_or(0.0);

    // Simulate ticket lock scenario (aligned with source)
    if ticket_id.contains("ticket_locked") {
        return Err("Ticket locked by another agent, will retry".to_string());
    }

    let now = chrono::Utc::now().to_rfc3339();

    info!(
        "Ticket updated: ticket_id={}, status=resolved, delegated_task={}",
        ticket_id, delegated_task_id
    );

    // Output keys aligned with source: ticket_updated, ticket_id, previous_status, new_status,
    // resolution_note, updated_at, refund_completed, delegated_task_id, namespace
    Ok(json!({
        "ticket_updated": true,
        "ticket_id": ticket_id,
        "previous_status": "in_progress",
        "new_status": "resolved",
        "resolution_note": format!(
            "Refund of ${:.2} processed successfully. Delegated task ID: {}. Correlation ID: {}",
            refund_amount / 100.0,
            delegated_task_id,
            correlation_id
        ),
        "updated_at": now,
        "refund_completed": true,
        "delegated_task_id": delegated_task_id,
        "namespace": "customer_success_rs"
    }))
}
