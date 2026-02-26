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

use crate::types::customer_success::*;
use serde_json::Value;
use std::collections::HashMap;
use tracing::info;
use uuid::Uuid;

// ============================================================================
// Helper Functions
// ============================================================================

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

fn get_refund_policy(tier: &str) -> (i64, bool, f64) {
    match tier {
        "gold" => (60, false, 500.0),
        "premium" => (90, false, 1000.0),
        _ => (30, true, 100.0),
    }
}

// ============================================================================
// Step 1: Validate Refund Request
// ============================================================================

/// Validates the incoming refund request, checking for required fields and valid amounts.
pub fn validate_refund_request(context: &Value) -> Result<Value, String> {
    let input: ProcessRefundInput = serde_json::from_value(context.clone())
        .map_err(|e| format!("Invalid process refund input: {}", e))?;

    let ticket_id = &input.ticket_id;
    let customer_id = &input.customer_id;
    let refund_amount = input.refund_amount;
    let customer_email = &input.customer_email;

    let order_ref = context
        .get("order_id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let reason = input.refund_reason.as_deref().unwrap_or("No reason provided");

    if refund_amount <= 0.0 {
        return Err("Refund amount must be positive".to_string());
    }
    if refund_amount > 10000.0 {
        return Err(format!(
            "Refund amount ${:.2} exceeds maximum single refund limit of $10,000",
            refund_amount
        ));
    }

    if ticket_id.contains("ticket_closed") {
        return Err("Cannot process refund for closed ticket".to_string());
    }
    if ticket_id.contains("ticket_cancelled") {
        return Err("Cannot process refund for cancelled ticket".to_string());
    }

    let customer_tier = determine_customer_tier(customer_id);
    let payment_id = format!("pay_{}", &Uuid::new_v4().to_string().replace('-', "")[..12]);
    let request_id = format!("req_{}", &Uuid::new_v4().to_string().replace('-', "")[..12]);
    let now = chrono::Utc::now().to_rfc3339();
    let purchase_date = (chrono::Utc::now() - chrono::Duration::days(30)).to_rfc3339();

    info!(
        "Refund request validated: ticket={}, customer_tier={}, amount=${:.2}",
        ticket_id, customer_tier, refund_amount
    );

    let result = ValidateRefundRequestResult {
        request_id,
        ticket_id: ticket_id.to_string(),
        eligible: true,
        amount: refund_amount,
        validated_at: now.clone(),
        customer_email: Some(customer_email.to_string()),
        customer_id: Some(customer_id.to_string()),
        customer_tier: Some(customer_tier.to_string()),
        namespace: Some("customer_success_rs".to_string()),
        order_ref: Some(order_ref.to_string()),
        original_purchase_date: Some(purchase_date),
        payment_id: Some(payment_id),
        reason: Some(reason.to_string()),
        request_validated: Some(true),
        ticket_status: Some("open".to_string()),
        validation_hash: None,
        validation_timestamp: Some(now),
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Step 2: Check Refund Policy
// ============================================================================

/// Evaluates the refund request against company refund policies.
pub fn check_refund_policy(
    context: &Value,
    dependency_results: &HashMap<String, Value>,
) -> Result<Value, String> {
    let validation: ValidateRefundRequestResult = dependency_results
        .get("validate_refund_request")
        .ok_or("Missing validate_refund_request dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize validation result: {}", e))
        })?;

    if !validation.request_validated.unwrap_or(false) {
        return Err("Request validation must be completed before policy check".to_string());
    }

    let customer_tier = validation.customer_tier.as_deref().unwrap_or("standard");

    let refund_amount = context
        .get("refund_amount")
        .and_then(|v| v.as_f64())
        .unwrap_or(validation.amount);

    let (window_days, requires_approval, max_amount) = get_refund_policy(customer_tier);
    let days_since_purchase: i64 = 30;
    let within_window = days_since_purchase <= window_days;
    let within_amount_limit = refund_amount <= max_amount;

    if !within_window {
        return Err(format!(
            "Refund request outside policy window: {} days (max: {} days)",
            days_since_purchase, window_days
        ));
    }

    if !within_amount_limit {
        return Err(format!(
            "Refund amount exceeds policy limit: ${:.2} (max: ${:.2})",
            refund_amount, max_amount
        ));
    }

    let approval_path = if requires_approval {
        if refund_amount > 50.0 {
            "director"
        } else {
            "manager"
        }
    } else {
        "auto"
    };

    let policy_id = format!("pol_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);
    let now = chrono::Utc::now().to_rfc3339();

    info!(
        "Policy check passed: customer_tier={}, requires_approval={}, amount=${:.2}",
        customer_tier, requires_approval, refund_amount
    );

    let result = CheckRefundPolicyResult {
        request_id: validation.request_id,
        policy_compliant: true,
        requires_approval,
        policy_id,
        checked_at: now.clone(),
        customer_tier: Some(customer_tier.to_string()),
        refund_window_days: Some(window_days),
        days_since_purchase: Some(days_since_purchase),
        within_refund_window: Some(within_window),
        max_allowed_amount: Some(max_amount),
        amount_tier: None,
        approval_path: Some(approval_path.to_string()),
        namespace: Some("customer_success_rs".to_string()),
        policy_checked: Some(true),
        policy_checked_at: Some(now),
        policy_version: Some("v2.1".to_string()),
        requires_review: None,
        rules_applied: Some(vec![
            "refund_window_check".to_string(),
            "amount_limit_check".to_string(),
            "tier_policy_check".to_string(),
        ]),
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Step 3: Get Manager Approval
// ============================================================================

/// Routes the refund for manager approval if policies require it.
pub fn get_manager_approval(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let policy: CheckRefundPolicyResult = dependency_results
        .get("check_refund_policy")
        .ok_or("Missing check_refund_policy dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize policy result: {}", e))
        })?;

    let validation: ValidateRefundRequestResult = dependency_results
        .get("validate_refund_request")
        .ok_or("Missing validate_refund_request dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize validation result: {}", e))
        })?;

    if !policy.policy_checked.unwrap_or(false) {
        return Err("Policy check must be completed before approval".to_string());
    }

    let customer_tier = policy.customer_tier.as_deref().unwrap_or("standard");
    let customer_id = validation.customer_id.as_deref().unwrap_or("unknown");

    let now = chrono::Utc::now().to_rfc3339();

    if policy.requires_approval {
        if validation.ticket_id.contains("ticket_denied") {
            return Err("Manager denied refund request".to_string());
        }
        if validation.ticket_id.contains("ticket_pending") {
            return Err("Waiting for manager approval (retryable)".to_string());
        }

        let approval_id = format!("appr_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);
        let manager_id = format!("mgr_{}", (validation.ticket_id.len() % 5) + 1);

        info!(
            "Manager approval obtained: approval_id={}, manager_id={}",
            approval_id, manager_id
        );

        let result = GetManagerApprovalResult {
            request_id: validation.request_id,
            approved: true,
            approved_at: now,
            approval_id: Some(approval_id),
            approver: Some(manager_id.clone()),
            manager_id: Some(manager_id),
            approval_note: Some(format!(
                "Approved refund request for customer {}",
                customer_id
            )),
            approval_obtained: Some(true),
            approval_path: Some("manager".to_string()),
            approval_required: Some(true),
            auto_approved: Some(false),
            amount_approved: None,
            manager_notes: None,
            namespace: Some("customer_success_rs".to_string()),
        };

        serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
    } else {
        info!(
            "Auto-approved for tier={}, ticket={}",
            customer_tier, validation.ticket_id
        );

        let result = GetManagerApprovalResult {
            request_id: validation.request_id,
            approved: true,
            approved_at: now,
            approval_id: None,
            approver: None,
            manager_id: None,
            approval_note: Some(format!("Auto-approved for customer tier {}", customer_tier)),
            approval_obtained: Some(true),
            approval_path: Some("auto".to_string()),
            approval_required: Some(false),
            auto_approved: Some(true),
            amount_approved: None,
            manager_notes: None,
            namespace: Some("customer_success_rs".to_string()),
        };

        serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
    }
}

// ============================================================================
// Step 4: Execute Refund Workflow
// ============================================================================

/// Coordinates the actual refund execution.
pub fn execute_refund_workflow(
    dependency_results: &HashMap<String, Value>,
) -> Result<Value, String> {
    let approval: GetManagerApprovalResult = dependency_results
        .get("get_manager_approval")
        .ok_or("Missing get_manager_approval dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize approval result: {}", e))
        })?;

    let validation: ValidateRefundRequestResult = dependency_results
        .get("validate_refund_request")
        .ok_or("Missing validate_refund_request dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize validation result: {}", e))
        })?;

    if !approval.approval_obtained.unwrap_or(false) {
        return Err("Manager approval must be obtained before executing refund".to_string());
    }

    let payment_id = validation.payment_id.as_deref().unwrap_or("");
    if payment_id.is_empty() {
        return Err("Payment ID not found in validation results".to_string());
    }

    let refund_id = format!(
        "rfnd_{}",
        &Uuid::new_v4().to_string().replace('-', "")[..12]
    );
    let correlation_id = format!(
        "cs-corr_{}",
        &Uuid::new_v4().to_string().replace('-', "")[..12]
    );
    let task_id = format!("task_{}", Uuid::new_v4());
    let now = chrono::Utc::now().to_rfc3339();

    info!(
        "Refund workflow delegated: task_id={}, correlation_id={}",
        task_id, correlation_id
    );

    let result = ExecuteRefundWorkflowResult {
        request_id: validation.request_id,
        refund_id,
        status: "processing".to_string(),
        amount_refunded: validation.amount,
        executed_at: now.clone(),
        correlation_id: Some(correlation_id),
        currency: Some("USD".to_string()),
        delegated_task_id: Some(task_id),
        delegated_task_status: Some("created".to_string()),
        delegation_timestamp: Some(now),
        estimated_arrival: None,
        namespace: Some("customer_success_rs".to_string()),
        order_ref: validation.order_ref,
        refund_method: Some("original_payment_method".to_string()),
        target_namespace: Some("payments_rs".to_string()),
        target_workflow: Some("process_refund".to_string()),
        task_delegated: Some(true),
        transaction_ref: None,
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Step 5: Update Ticket Status
// ============================================================================

/// Updates the support ticket with the final refund outcome.
pub fn update_ticket_status(
    context: &Value,
    dependency_results: &HashMap<String, Value>,
) -> Result<Value, String> {
    let execution: ExecuteRefundWorkflowResult = dependency_results
        .get("execute_refund_workflow")
        .ok_or("Missing execute_refund_workflow dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize execution result: {}", e))
        })?;

    let validation: ValidateRefundRequestResult = dependency_results
        .get("validate_refund_request")
        .ok_or("Missing validate_refund_request dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize validation result: {}", e))
        })?;

    if !execution.task_delegated.unwrap_or(false) {
        return Err("Refund workflow must be executed before updating ticket".to_string());
    }

    if validation.ticket_id.contains("ticket_locked") {
        return Err("Ticket locked by another agent, will retry".to_string());
    }

    let refund_amount = context
        .get("refund_amount")
        .and_then(|v| v.as_f64())
        .unwrap_or(validation.amount);

    let correlation_id = execution.correlation_id.as_deref().unwrap_or("unknown");
    let delegated_task_id = execution.delegated_task_id.as_deref().unwrap_or("unknown");

    let now = chrono::Utc::now().to_rfc3339();

    info!(
        "Ticket updated: ticket_id={}, status=resolved, delegated_task={}",
        validation.ticket_id, delegated_task_id
    );

    let result = UpdateTicketStatusResult {
        ticket_id: validation.ticket_id,
        request_id: validation.request_id,
        ticket_updated: true,
        new_status: "resolved".to_string(),
        resolved_at: now.clone(),
        previous_status: Some("in_progress".to_string()),
        resolution: Some("refund_processed".to_string()),
        resolution_note: Some(format!(
            "Refund of ${:.2} processed successfully. Correlation ID: {}",
            refund_amount, correlation_id
        )),
        customer_notified: Some(true),
        notification_channel: Some("email".to_string()),
        refund_completed: Some(true),
        refund_id: Some(execution.refund_id),
        amount_refunded: Some(refund_amount),
        delegated_task_id: Some(delegated_task_id.to_string()),
        namespace: Some("customer_success_rs".to_string()),
        ticket_status: Some("resolved".to_string()),
        updated_at: Some(now),
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}
