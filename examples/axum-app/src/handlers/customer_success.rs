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
// Step 1: Validate Refund Request
// ============================================================================

/// Validates the incoming refund request, checking for required fields,
/// valid amounts, and order existence. Enriches the request with order details.
pub fn validate_refund_request(context: &Value) -> Result<Value, String> {
    let ticket_id = context.get("ticket_id")
        .and_then(|v| v.as_str())
        .ok_or("Missing ticket_id in context")?;

    let customer_email = context.get("customer_email")
        .and_then(|v| v.as_str())
        .ok_or("Missing customer_email in context")?;

    let order_id = context.get("order_id")
        .and_then(|v| v.as_str())
        .ok_or("Missing order_id in context")?;

    let refund_amount = context.get("refund_amount")
        .and_then(|v| v.as_f64())
        .ok_or("Missing or invalid refund_amount in context")?;

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

    // Simulate order lookup (in production, this would query the orders database)
    let order_total = refund_amount * 1.5; // Simulated: order was larger than refund
    let order_date = "2025-11-15T10:30:00Z";
    let days_since_order = 30; // Simulated

    if refund_amount > order_total {
        return Err(format!(
            "Refund amount ${:.2} exceeds order total ${:.2}",
            refund_amount, order_total
        ));
    }

    let validation_id = format!("val_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);

    info!(
        "Refund request validated: ticket={}, order={}, amount=${:.2}, reason={}",
        ticket_id, order_id, refund_amount, reason
    );

    Ok(json!({
        "validation_id": validation_id,
        "ticket_id": ticket_id,
        "customer_email": customer_email,
        "order_id": order_id,
        "order_total": order_total,
        "order_date": order_date,
        "days_since_order": days_since_order,
        "refund_amount": refund_amount,
        "refund_percentage": ((refund_amount / order_total) * 100.0).round(),
        "reason": reason,
        "is_valid": true,
        "validated_at": chrono::Utc::now().to_rfc3339()
    }))
}

// ============================================================================
// Step 2: Check Refund Policy
// ============================================================================

/// Evaluates the refund request against company refund policies.
/// Determines if the refund requires manager approval based on amount and timing.
pub fn check_refund_policy(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let validation = dependency_results.get("validate_refund_request")
        .ok_or("Missing validate_refund_request dependency")?;

    let refund_amount = validation.get("refund_amount").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let days_since_order = validation.get("days_since_order").and_then(|v| v.as_i64()).unwrap_or(0);
    let refund_percentage = validation.get("refund_percentage").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let order_id = validation.get("order_id").and_then(|v| v.as_str()).unwrap_or("unknown");

    let mut policy_checks = Vec::new();
    let mut requires_approval = false;
    let mut approval_reason = Vec::new();

    // Policy 1: Time-based (30-day return window)
    let within_return_window = days_since_order <= 30;
    policy_checks.push(json!({
        "policy": "return_window",
        "description": "30-day return policy",
        "passed": within_return_window,
        "details": format!("{} days since order", days_since_order)
    }));
    if !within_return_window {
        requires_approval = true;
        approval_reason.push("Outside 30-day return window".to_string());
    }

    // Policy 2: Amount threshold (auto-approve under $100)
    let under_auto_threshold = refund_amount < 100.0;
    policy_checks.push(json!({
        "policy": "amount_threshold",
        "description": "Auto-approve refunds under $100",
        "passed": under_auto_threshold,
        "details": format!("Refund amount: ${:.2}", refund_amount)
    }));
    if !under_auto_threshold {
        requires_approval = true;
        approval_reason.push(format!("Amount ${:.2} exceeds auto-approve threshold", refund_amount));
    }

    // Policy 3: Partial refund check (full refunds need review if over $250)
    let is_partial = refund_percentage < 100.0;
    let partial_ok = is_partial || refund_amount < 250.0;
    policy_checks.push(json!({
        "policy": "full_refund_review",
        "description": "Full refunds over $250 require review",
        "passed": partial_ok,
        "details": format!("Refund is {:.0}% of order (${:.2})", refund_percentage, refund_amount)
    }));
    if !partial_ok {
        requires_approval = true;
        approval_reason.push("Full refund exceeds $250 threshold".to_string());
    }

    let all_passed = policy_checks.iter().all(|p| p["passed"].as_bool().unwrap_or(false));

    info!(
        "Policy check for order {}: {} checks, approval_required={}, all_passed={}",
        order_id, policy_checks.len(), requires_approval, all_passed
    );

    Ok(json!({
        "policy_checks": policy_checks,
        "all_policies_passed": all_passed,
        "requires_manager_approval": requires_approval,
        "approval_reasons": approval_reason,
        "auto_approvable": !requires_approval,
        "checked_at": chrono::Utc::now().to_rfc3339()
    }))
}

// ============================================================================
// Step 3: Get Manager Approval
// ============================================================================

/// Routes the refund for manager approval if policies require it.
/// For refunds that pass all policies, auto-approval is granted.
pub fn get_manager_approval(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let policy_result = dependency_results.get("check_refund_policy")
        .ok_or("Missing check_refund_policy dependency")?;

    let validation = dependency_results.get("validate_refund_request")
        .ok_or("Missing validate_refund_request dependency")?;

    let requires_approval = policy_result.get("requires_manager_approval")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    let approval_reasons = policy_result.get("approval_reasons")
        .cloned()
        .unwrap_or(json!([]));

    let refund_amount = validation.get("refund_amount")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);

    let ticket_id = validation.get("ticket_id")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let approval_id = format!("appr_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);

    if !requires_approval {
        info!("Auto-approved refund for ticket {}: ${:.2}", ticket_id, refund_amount);
        return Ok(json!({
            "approval_id": approval_id,
            "ticket_id": ticket_id,
            "approval_type": "auto",
            "approved": true,
            "approver": "system",
            "refund_amount": refund_amount,
            "notes": "Auto-approved: all policies passed",
            "approved_at": chrono::Utc::now().to_rfc3339()
        }));
    }

    // Simulate manager review (in production, this might be async/deferred)
    let approved = refund_amount < 5000.0; // Simulate: approve under $5k
    let manager = "manager@company.com";

    info!(
        "Manager {} {} refund for ticket {}: ${:.2} (reasons: {:?})",
        if approved { "approved" } else { "rejected" },
        manager, ticket_id, refund_amount, approval_reasons
    );

    Ok(json!({
        "approval_id": approval_id,
        "ticket_id": ticket_id,
        "approval_type": "manual",
        "approved": approved,
        "approver": manager,
        "refund_amount": refund_amount,
        "approval_reasons": approval_reasons,
        "notes": if approved {
            "Approved after manager review"
        } else {
            "Rejected: exceeds manager authority limit"
        },
        "reviewed_at": chrono::Utc::now().to_rfc3339()
    }))
}

// ============================================================================
// Step 4: Execute Refund Workflow
// ============================================================================

/// Coordinates the actual refund execution by gathering all approvals
/// and creating the refund execution record.
pub fn execute_refund_workflow(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let approval = dependency_results.get("get_manager_approval")
        .ok_or("Missing get_manager_approval dependency")?;

    let validation = dependency_results.get("validate_refund_request")
        .ok_or("Missing validate_refund_request dependency")?;

    let approved = approval.get("approved").and_then(|v| v.as_bool()).unwrap_or(false);

    if !approved {
        return Ok(json!({
            "status": "rejected",
            "reason": "Manager approval was not granted",
            "ticket_id": validation.get("ticket_id").and_then(|v| v.as_str()).unwrap_or("unknown"),
            "executed_at": chrono::Utc::now().to_rfc3339()
        }));
    }

    let refund_amount = validation.get("refund_amount").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let order_id = validation.get("order_id").and_then(|v| v.as_str()).unwrap_or("unknown");
    let ticket_id = validation.get("ticket_id").and_then(|v| v.as_str()).unwrap_or("unknown");
    let approval_id = approval.get("approval_id").and_then(|v| v.as_str()).unwrap_or("unknown");

    let execution_id = format!("exec_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);

    info!(
        "Refund workflow executed: ticket={}, order={}, amount=${:.2}, approval={}",
        ticket_id, order_id, refund_amount, approval_id
    );

    Ok(json!({
        "execution_id": execution_id,
        "ticket_id": ticket_id,
        "order_id": order_id,
        "refund_amount": refund_amount,
        "approval_id": approval_id,
        "status": "executed",
        "payment_refund_initiated": true,
        "executed_at": chrono::Utc::now().to_rfc3339()
    }))
}

// ============================================================================
// Step 5: Update Ticket Status
// ============================================================================

/// Updates the support ticket with the final refund outcome.
/// Records the complete refund timeline for audit purposes.
pub fn update_ticket_status(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let execution = dependency_results.get("execute_refund_workflow")
        .ok_or("Missing execute_refund_workflow dependency")?;

    let validation = dependency_results.get("validate_refund_request")
        .ok_or("Missing validate_refund_request dependency")?;

    let approval = dependency_results.get("get_manager_approval")
        .ok_or("Missing get_manager_approval dependency")?;

    let ticket_id = validation.get("ticket_id").and_then(|v| v.as_str()).unwrap_or("unknown");
    let customer_email = validation.get("customer_email").and_then(|v| v.as_str()).unwrap_or("unknown");
    let execution_status = execution.get("status").and_then(|v| v.as_str()).unwrap_or("unknown");
    let approved = approval.get("approved").and_then(|v| v.as_bool()).unwrap_or(false);

    let ticket_status = if execution_status == "executed" && approved {
        "resolved"
    } else if !approved {
        "rejected"
    } else {
        "pending_review"
    };

    let resolution_note = match ticket_status {
        "resolved" => format!(
            "Refund of ${:.2} processed successfully for order {}",
            validation.get("refund_amount").and_then(|v| v.as_f64()).unwrap_or(0.0),
            validation.get("order_id").and_then(|v| v.as_str()).unwrap_or("unknown")
        ),
        "rejected" => "Refund request was not approved. Customer has been notified.".to_string(),
        _ => "Refund is pending further review.".to_string(),
    };

    info!(
        "Ticket {} updated to '{}' for customer {}",
        ticket_id, ticket_status, customer_email
    );

    Ok(json!({
        "ticket_id": ticket_id,
        "customer_email": customer_email,
        "previous_status": "in_progress",
        "new_status": ticket_status,
        "resolution_note": resolution_note,
        "timeline": {
            "opened": validation.get("validated_at"),
            "policy_checked": dependency_results.get("check_refund_policy")
                .and_then(|r| r.get("checked_at")),
            "approved": approval.get("reviewed_at").or_else(|| approval.get("approved_at")),
            "executed": execution.get("executed_at"),
            "closed": chrono::Utc::now().to_rfc3339()
        },
        "updated_at": chrono::Utc::now().to_rfc3339()
    }))
}
