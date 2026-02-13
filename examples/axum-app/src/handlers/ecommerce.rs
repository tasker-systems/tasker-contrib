//! # E-commerce Order Processing Handlers
//!
//! Native Rust implementation of the e-commerce order processing workflow.
//! Demonstrates a 5-step linear chain with dependency data passing.
//!
//! ## Steps
//!
//! 1. **ecommerce_validate_cart**: Validate items, calc subtotal/tax(8%)/shipping/total
//! 2. **ecommerce_process_payment**: Simulate payment gateway with test tokens
//! 3. **ecommerce_update_inventory**: Create inventory reservations
//! 4. **ecommerce_create_order**: Aggregate upstream data, generate order ID
//! 5. **ecommerce_send_confirmation**: Simulate confirmation email

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use tracing::{error, info};
use uuid::Uuid;

// ============================================================================
// Data Types
// ============================================================================

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CartItem {
    pub product_id: i64,
    pub quantity: i64,
}

#[derive(Debug, Clone)]
struct Product {
    id: i64,
    name: String,
    price: f64,
    stock: i64,
}

fn get_product_catalog() -> HashMap<i64, Product> {
    let mut catalog = HashMap::new();
    catalog.insert(1, Product { id: 1, name: "Widget A".into(), price: 29.99, stock: 100 });
    catalog.insert(2, Product { id: 2, name: "Widget B".into(), price: 49.99, stock: 50 });
    catalog.insert(3, Product { id: 3, name: "Widget C".into(), price: 99.99, stock: 25 });
    catalog.insert(4, Product { id: 4, name: "Gadget X".into(), price: 149.99, stock: 30 });
    catalog.insert(5, Product { id: 5, name: "Gadget Y".into(), price: 199.99, stock: 15 });
    catalog
}

// ============================================================================
// Step 1: Validate Cart
// ============================================================================

/// Validates cart items against the product catalog, checks stock availability,
/// and calculates pricing including subtotal, tax (8%), shipping, and total.
pub fn validate_cart(context: &Value) -> Result<Value, String> {
    let cart_items: Vec<CartItem> = serde_json::from_value(
        context.get("cart_items").cloned().unwrap_or(json!([])),
    )
    .map_err(|e| format!("Invalid cart_items format: {}", e))?;

    if cart_items.is_empty() {
        return Err("Cart cannot be empty".to_string());
    }

    let catalog = get_product_catalog();
    let mut validated_items = Vec::new();
    let mut subtotal = 0.0_f64;
    let mut item_count = 0_i64;

    for cart_item in &cart_items {
        let product = catalog
            .get(&cart_item.product_id)
            .ok_or_else(|| format!("Product {} not found in catalog", cart_item.product_id))?;

        if cart_item.quantity > product.stock {
            return Err(format!(
                "Insufficient stock for {}: requested {}, available {}",
                product.name, cart_item.quantity, product.stock
            ));
        }

        if cart_item.quantity <= 0 {
            return Err(format!(
                "Invalid quantity {} for product {}",
                cart_item.quantity, product.name
            ));
        }

        let line_total = product.price * cart_item.quantity as f64;
        subtotal += line_total;
        item_count += cart_item.quantity;

        validated_items.push(json!({
            "product_id": product.id,
            "product_name": product.name,
            "quantity": cart_item.quantity,
            "unit_price": product.price,
            "line_total": (line_total * 100.0).round() / 100.0
        }));
    }

    let tax = (subtotal * 0.08 * 100.0).round() / 100.0;
    let shipping = if subtotal > 100.0 { 0.0 } else { 5.99 };
    let total = ((subtotal + tax + shipping) * 100.0).round() / 100.0;

    info!(
        "Cart validated: {} items, subtotal=${:.2}, tax=${:.2}, shipping=${:.2}, total=${:.2}",
        item_count, subtotal, tax, shipping, total
    );

    Ok(json!({
        "validated_items": validated_items,
        "subtotal": subtotal,
        "tax": tax,
        "shipping": shipping,
        "total": total,
        "item_count": item_count
    }))
}

// ============================================================================
// Step 2: Process Payment
// ============================================================================

/// Simulates payment processing through a payment gateway.
/// Supports test tokens for simulating various payment outcomes:
/// - `tok_test_success` or any other token: successful payment
/// - `tok_test_declined`: card declined (permanent error)
/// - `tok_test_insufficient_funds`: insufficient funds (permanent error)
/// - `tok_test_network_error`: gateway unreachable (retryable error)
pub fn process_payment(context: &Value, dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let payment_info = context.get("payment_info")
        .ok_or("Missing payment_info in task context")?;

    let token = payment_info.get("token")
        .and_then(|v| v.as_str())
        .unwrap_or("tok_test_success");

    let method = payment_info.get("method")
        .and_then(|v| v.as_str())
        .unwrap_or("credit_card");

    // Get cart total from validate_cart dependency
    let cart_result = dependency_results.get("validate_cart")
        .ok_or("Missing validate_cart dependency result")?;
    let cart_total = cart_result.get("total")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);

    // Check for test failure tokens
    match token {
        "tok_test_declined" => {
            return Err("Card was declined".to_string());
        }
        "tok_test_insufficient_funds" => {
            return Err("Insufficient funds on card".to_string());
        }
        "tok_test_network_error" => {
            return Err("Payment gateway unreachable (retryable)".to_string());
        }
        _ => {}
    }

    let transaction_id = format!("txn_{}", &Uuid::new_v4().to_string().replace('-', "")[..12]);
    let authorization_code = format!("AUTH{}", &Uuid::new_v4().to_string().replace('-', "")[..6].to_uppercase());

    info!(
        "Payment processed: ${:.2} via {} (txn: {}, auth: {})",
        cart_total, method, transaction_id, authorization_code
    );

    Ok(json!({
        "transaction_id": transaction_id,
        "authorization_code": authorization_code,
        "amount_charged": cart_total,
        "payment_method": method,
        "status": "completed",
        "gateway": "stripe_mock",
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}

// ============================================================================
// Step 3: Update Inventory
// ============================================================================

/// Creates inventory reservations for each validated cart item.
/// Each reservation gets a unique ID and is marked with a 24-hour expiration window.
pub fn update_inventory(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let cart_result = dependency_results.get("validate_cart")
        .ok_or("Missing validate_cart dependency result")?;

    let validated_items = cart_result.get("validated_items")
        .and_then(|v| v.as_array())
        .ok_or("Missing validated_items in cart result")?;

    let mut reservations = Vec::new();
    let mut total_reserved = 0_i64;
    let reservation_expires = chrono::Utc::now() + chrono::Duration::hours(24);

    for item in validated_items {
        let product_id = item.get("product_id").and_then(|v| v.as_i64()).unwrap_or(0);
        let product_name = item.get("product_name").and_then(|v| v.as_str()).unwrap_or("Unknown");
        let quantity = item.get("quantity").and_then(|v| v.as_i64()).unwrap_or(0);
        let reservation_id = format!("res_{}", &Uuid::new_v4().to_string().replace('-', "")[..8]);

        reservations.push(json!({
            "reservation_id": reservation_id,
            "product_id": product_id,
            "product_name": product_name,
            "quantity_reserved": quantity,
            "status": "reserved",
            "warehouse": "WH-PRIMARY",
            "expires_at": reservation_expires.to_rfc3339()
        }));
        total_reserved += quantity;
    }

    info!(
        "Inventory reserved: {} units across {} products",
        total_reserved, reservations.len()
    );

    Ok(json!({
        "reservations": reservations,
        "total_items_reserved": total_reserved,
        "reservation_timestamp": chrono::Utc::now().to_rfc3339(),
        "expiration": reservation_expires.to_rfc3339()
    }))
}

// ============================================================================
// Step 4: Create Order
// ============================================================================

/// Aggregates data from cart validation, payment processing, and inventory reservation
/// to create a complete order record. Generates an order ID in the format ORD-{date}-{hex}.
pub fn create_order(context: &Value, dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let customer_info = context.get("customer_info")
        .ok_or("Missing customer_info in task context")?;

    let customer_email = customer_info.get("email")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown@example.com");

    let customer_name = customer_info.get("name")
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown Customer");

    // Collect data from all upstream steps
    let cart_result = dependency_results.get("validate_cart")
        .ok_or("Missing validate_cart dependency")?;

    let payment_result = dependency_results.get("process_payment")
        .ok_or("Missing process_payment dependency")?;

    let inventory_result = dependency_results.get("update_inventory")
        .ok_or("Missing update_inventory dependency")?;

    let validated_items = cart_result.get("validated_items").cloned().unwrap_or(json!([]));
    let order_total = cart_result.get("total").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let subtotal = cart_result.get("subtotal").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let tax = cart_result.get("tax").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let shipping = cart_result.get("shipping").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let transaction_id = payment_result.get("transaction_id").and_then(|v| v.as_str()).unwrap_or("unknown");
    let reservations = inventory_result.get("reservations").cloned().unwrap_or(json!([]));

    // Generate order ID: ORD-{YYYYMMDD}-{hex}
    let date_str = chrono::Utc::now().format("%Y%m%d").to_string();
    let hex_suffix = &Uuid::new_v4().to_string().replace('-', "")[..6].to_uppercase();
    let order_id = format!("ORD-{}-{}", date_str, hex_suffix);

    info!("Order created: {} for {} (total: ${:.2})", order_id, customer_email, order_total);

    Ok(json!({
        "order_id": order_id,
        "customer": {
            "email": customer_email,
            "name": customer_name
        },
        "items": validated_items,
        "pricing": {
            "subtotal": subtotal,
            "tax": tax,
            "shipping": shipping,
            "total": order_total
        },
        "payment": {
            "transaction_id": transaction_id,
            "amount": order_total
        },
        "inventory_reservations": reservations,
        "status": "confirmed",
        "created_at": chrono::Utc::now().to_rfc3339()
    }))
}

// ============================================================================
// Step 5: Send Confirmation
// ============================================================================

/// Simulates sending an order confirmation email to the customer.
/// Generates a unique email ID and includes order summary details.
pub fn send_confirmation(context: &Value, dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let customer_info = context.get("customer_info")
        .ok_or("Missing customer_info in task context")?;

    let customer_email = customer_info.get("email")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown@example.com");

    let order_result = dependency_results.get("create_order")
        .ok_or("Missing create_order dependency")?;

    let order_id = order_result.get("order_id")
        .and_then(|v| v.as_str())
        .unwrap_or("ORD-UNKNOWN");

    let order_total = order_result
        .get("pricing")
        .and_then(|p| p.get("total"))
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);

    let item_count = dependency_results
        .get("validate_cart")
        .and_then(|r| r.get("item_count"))
        .and_then(|v| v.as_i64())
        .unwrap_or(0);

    let email_id = format!("email_{}", &Uuid::new_v4().to_string().replace('-', "")[..12]);
    let subject = format!("Order Confirmation - {}", order_id);

    info!(
        "Confirmation sent: {} to {} for order {} (${:.2})",
        email_id, customer_email, order_id, order_total
    );

    Ok(json!({
        "email_id": email_id,
        "recipient": customer_email,
        "subject": subject,
        "order_id": order_id,
        "summary": {
            "item_count": item_count,
            "order_total": order_total
        },
        "template": "order_confirmation_v2",
        "status": "sent",
        "sent_at": chrono::Utc::now().to_rfc3339()
    }))
}
