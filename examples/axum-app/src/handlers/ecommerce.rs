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

use crate::types::ecommerce::*;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use tracing::info;
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
    sku: String,
    price: f64,
    stock: i64,
}

fn get_product_catalog() -> HashMap<i64, Product> {
    let mut catalog = HashMap::new();
    catalog.insert(
        1,
        Product {
            id: 1,
            name: "Widget A".into(),
            sku: "WGT-A-001".into(),
            price: 29.99,
            stock: 100,
        },
    );
    catalog.insert(
        2,
        Product {
            id: 2,
            name: "Widget B".into(),
            sku: "WGT-B-002".into(),
            price: 49.99,
            stock: 50,
        },
    );
    catalog.insert(
        3,
        Product {
            id: 3,
            name: "Widget C".into(),
            sku: "WGT-C-003".into(),
            price: 99.99,
            stock: 25,
        },
    );
    catalog.insert(
        4,
        Product {
            id: 4,
            name: "Gadget X".into(),
            sku: "GDG-X-004".into(),
            price: 149.99,
            stock: 30,
        },
    );
    catalog.insert(
        5,
        Product {
            id: 5,
            name: "Gadget Y".into(),
            sku: "GDG-Y-005".into(),
            price: 199.99,
            stock: 15,
        },
    );
    catalog
}

// ============================================================================
// Step 1: Validate Cart
// ============================================================================

/// Validates cart items against the product catalog, checks stock availability,
/// and calculates pricing including subtotal, tax (8%), shipping, and total.
pub fn validate_cart(context: &Value) -> Result<Value, String> {
    let input: OrderProcessingInput = serde_json::from_value(context.clone())
        .map_err(|e| format!("Invalid order processing input: {}", e))?;

    let cart_items: Vec<CartItem> = input
        .cart_items
        .iter()
        .map(|item| CartItem {
            product_id: item.product_id,
            quantity: item.quantity,
        })
        .collect();

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

        validated_items.push(ValidateCartResultValidatedItems {
            sku: product.sku.clone(),
            name: product.name.clone(),
            quantity: cart_item.quantity,
            unit_price: product.price,
            line_total: (line_total * 100.0).round() / 100.0,
        });
    }

    let tax_rate = 0.08;
    let tax = (subtotal * tax_rate * 100.0).round() / 100.0;
    let shipping = if subtotal > 100.0 { 0.0 } else { 5.99 };
    let total = ((subtotal + tax + shipping) * 100.0).round() / 100.0;

    info!(
        "Cart validated: {} items, subtotal=${:.2}, tax=${:.2}, shipping=${:.2}, total=${:.2}",
        item_count, subtotal, tax, shipping, total
    );

    let result = ValidateCartResult {
        validated_items,
        subtotal,
        tax_rate,
        tax,
        shipping,
        total,
        item_count,
        validated_at: chrono::Utc::now().to_rfc3339(),
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Step 2: Process Payment
// ============================================================================

/// Simulates payment processing through a payment gateway.
/// Supports test tokens for simulating various payment outcomes.
pub fn process_payment(
    context: &Value,
    dependency_results: &HashMap<String, Value>,
) -> Result<Value, String> {
    let token = context
        .get("payment_token")
        .and_then(|v| v.as_str())
        .unwrap_or("tok_test_success");

    let method = context
        .get("payment_method")
        .and_then(|v| v.as_str())
        .unwrap_or("credit_card");

    let cart: ValidateCartResult = dependency_results
        .get("validate_cart")
        .ok_or("Missing validate_cart dependency result".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize cart result: {}", e))
        })?;

    match token {
        "tok_test_declined" => return Err("Card was declined".to_string()),
        "tok_test_insufficient_funds" => return Err("Insufficient funds on card".to_string()),
        "tok_test_network_error" => {
            return Err("Payment gateway unreachable (retryable)".to_string())
        }
        _ => {}
    }

    let transaction_id = format!("txn_{}", &Uuid::new_v4().to_string().replace('-', "")[..12]);
    let authorization_code = format!(
        "AUTH{}",
        &Uuid::new_v4().to_string().replace('-', "")[..6].to_uppercase()
    );
    let payment_id = format!("pay_{}", &Uuid::new_v4().to_string().replace('-', "")[..12]);

    info!(
        "Payment processed: ${:.2} via {} (txn: {}, auth: {})",
        cart.total, method, transaction_id, authorization_code
    );

    let result = ProcessPaymentResult {
        payment_id,
        transaction_id,
        status: "completed".to_string(),
        amount_charged: cart.total,
        currency: "USD".to_string(),
        payment_method_type: method.to_string(),
        authorization_code,
        processed_at: chrono::Utc::now().to_rfc3339(),
        gateway_response: Some("approved".to_string()),
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Step 3: Update Inventory
// ============================================================================

/// Creates inventory reservations for each validated cart item.
pub fn update_inventory(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let cart: ValidateCartResult = dependency_results
        .get("validate_cart")
        .ok_or("Missing validate_cart dependency result".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize cart result: {}", e))
        })?;

    let mut updated_products = Vec::new();
    let mut total_reserved = 0_i64;
    let catalog = get_product_catalog();

    for item in &cart.validated_items {
        let product = catalog.values().find(|p| p.sku == item.sku);
        let previous_quantity = product.map(|p| p.stock).unwrap_or(100);
        let product_id = product
            .map(|p| format!("PROD-{}", p.id))
            .unwrap_or_else(|| "PROD-0".to_string());

        updated_products.push(UpdateInventoryResultUpdatedProducts {
            product_id,
            sku: item.sku.clone(),
            previous_quantity,
            new_quantity: previous_quantity - item.quantity,
            reserved: item.quantity,
        });
        total_reserved += item.quantity;
    }

    let inventory_log_id = format!(
        "inv_{}",
        &Uuid::new_v4().to_string().replace('-', "")[..12]
    );

    info!(
        "Inventory reserved: {} units across {} products",
        total_reserved,
        updated_products.len()
    );

    let result = UpdateInventoryResult {
        updated_products,
        total_items_reserved: total_reserved,
        inventory_log_id,
        updated_at: chrono::Utc::now().to_rfc3339(),
        inventory_changes: None,
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Step 4: Create Order
// ============================================================================

/// Aggregates data from cart validation, payment processing, and inventory reservation
/// to create a complete order record.
pub fn create_order(
    context: &Value,
    dependency_results: &HashMap<String, Value>,
) -> Result<Value, String> {
    let customer_email = context
        .get("customer_email")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown@example.com");

    let cart: ValidateCartResult = dependency_results
        .get("validate_cart")
        .ok_or("Missing validate_cart dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize cart result: {}", e))
        })?;

    let payment: ProcessPaymentResult = dependency_results
        .get("process_payment")
        .ok_or("Missing process_payment dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize payment result: {}", e))
        })?;

    let inventory: UpdateInventoryResult = dependency_results
        .get("update_inventory")
        .ok_or("Missing update_inventory dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize inventory result: {}", e))
        })?;

    // Convert validated items to order items (same shape)
    let items: Vec<CreateOrderResultItems> = cart
        .validated_items
        .iter()
        .map(|vi| CreateOrderResultItems {
            sku: vi.sku.clone(),
            name: vi.name.clone(),
            quantity: vi.quantity,
            unit_price: vi.unit_price,
            line_total: vi.line_total,
        })
        .collect();

    // Generate order ID: ORD-{YYYYMMDD}-{hex}
    let date_str = chrono::Utc::now().format("%Y%m%d").to_string();
    let hex_suffix = &Uuid::new_v4().to_string().replace('-', "")[..6].to_uppercase();
    let order_id = format!("ORD-{}-{}", date_str, hex_suffix);
    let order_number = order_id.clone();

    let estimated_delivery =
        (chrono::Utc::now() + chrono::Duration::days(5)).format("%Y-%m-%d").to_string();

    info!(
        "Order created: {} for {} (total: ${:.2})",
        order_id, customer_email, cart.total
    );

    let result = CreateOrderResult {
        order_id,
        order_number,
        status: "confirmed".to_string(),
        items,
        item_count: cart.item_count,
        subtotal: cart.subtotal,
        tax: cart.tax,
        shipping: cart.shipping,
        total: cart.total,
        total_amount: cart.total,
        customer_email: customer_email.to_string(),
        payment_id: payment.payment_id,
        transaction_id: payment.transaction_id,
        authorization_code: payment.authorization_code,
        inventory_log_id: inventory.inventory_log_id,
        estimated_delivery,
        created_at: chrono::Utc::now().to_rfc3339(),
        updated_products: None,
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Step 5: Send Confirmation
// ============================================================================

/// Simulates sending an order confirmation email to the customer.
pub fn send_confirmation(
    context: &Value,
    dependency_results: &HashMap<String, Value>,
) -> Result<Value, String> {
    let customer_email = context
        .get("customer_email")
        .and_then(|v| v.as_str())
        .unwrap_or("unknown@example.com");

    let order: CreateOrderResult = dependency_results
        .get("create_order")
        .ok_or("Missing create_order dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize order result: {}", e))
        })?;

    let message_id = format!(
        "email_{}",
        &Uuid::new_v4().to_string().replace('-', "")[..12]
    );
    let subject = format!("Order Confirmation - {}", order.order_id);

    info!(
        "Confirmation sent: {} to {} for order {}",
        message_id, customer_email, order.order_id
    );

    let result = SendConfirmationResult {
        message_id,
        status: "sent".to_string(),
        email_sent: true,
        recipient: customer_email.to_string(),
        subject,
        template: "order_confirmation_v2".to_string(),
        channel: "email".to_string(),
        sent_at: chrono::Utc::now().to_rfc3339(),
        body_preview: Some(format!("Your order {} has been confirmed!", order.order_id)),
        email_type: Some("transactional".to_string()),
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}
