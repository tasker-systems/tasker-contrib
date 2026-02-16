//! # Data Pipeline Analytics Handlers
//!
//! Native Rust implementation of the data pipeline analytics workflow.
//! Demonstrates a DAG pattern with 3 parallel extracts, 3 transforms,
//! aggregation, and insight generation.
//!
//! ## Steps
//!
//! **Extract Phase (parallel, no dependencies):**
//! 1. data_pipeline_extract_sales
//! 2. data_pipeline_extract_inventory
//! 3. data_pipeline_extract_customers
//!
//! **Transform Phase (each depends on its extract):**
//! 4. data_pipeline_transform_sales
//! 5. data_pipeline_transform_inventory
//! 6. data_pipeline_transform_customers
//!
//! **Aggregate Phase (depends on all 3 transforms):**
//! 7. data_pipeline_aggregate_metrics
//!
//! **Insights Phase (depends on aggregate):**
//! 8. data_pipeline_generate_insights

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use tracing::info;

// ============================================================================
// Sample Data Types
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SalesRecord {
    order_id: String,
    date: String,
    product_id: String,
    quantity: i64,
    amount: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct InventoryRecord {
    product_id: String,
    sku: String,
    warehouse: String,
    quantity_on_hand: i64,
    reorder_point: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CustomerRecord {
    customer_id: String,
    name: String,
    tier: String,
    lifetime_value: f64,
    join_date: String,
}

// ============================================================================
// Sample Data Generators
// ============================================================================

fn sample_sales() -> Vec<SalesRecord> {
    vec![
        SalesRecord { order_id: "ORD-001".into(), date: "2025-11-01".into(), product_id: "PROD-A".into(), quantity: 5, amount: 499.95 },
        SalesRecord { order_id: "ORD-002".into(), date: "2025-11-05".into(), product_id: "PROD-B".into(), quantity: 3, amount: 299.97 },
        SalesRecord { order_id: "ORD-003".into(), date: "2025-11-10".into(), product_id: "PROD-A".into(), quantity: 2, amount: 199.98 },
        SalesRecord { order_id: "ORD-004".into(), date: "2025-11-15".into(), product_id: "PROD-C".into(), quantity: 10, amount: 1499.90 },
        SalesRecord { order_id: "ORD-005".into(), date: "2025-11-18".into(), product_id: "PROD-B".into(), quantity: 7, amount: 699.93 },
        SalesRecord { order_id: "ORD-006".into(), date: "2025-11-22".into(), product_id: "PROD-A".into(), quantity: 4, amount: 399.96 },
        SalesRecord { order_id: "ORD-007".into(), date: "2025-11-25".into(), product_id: "PROD-D".into(), quantity: 1, amount: 249.99 },
    ]
}

fn sample_inventory() -> Vec<InventoryRecord> {
    vec![
        InventoryRecord { product_id: "PROD-A".into(), sku: "SKU-A-001".into(), warehouse: "WH-01".into(), quantity_on_hand: 150, reorder_point: 50 },
        InventoryRecord { product_id: "PROD-B".into(), sku: "SKU-B-002".into(), warehouse: "WH-01".into(), quantity_on_hand: 75, reorder_point: 25 },
        InventoryRecord { product_id: "PROD-C".into(), sku: "SKU-C-003".into(), warehouse: "WH-02".into(), quantity_on_hand: 200, reorder_point: 100 },
        InventoryRecord { product_id: "PROD-A".into(), sku: "SKU-A-001".into(), warehouse: "WH-02".into(), quantity_on_hand: 100, reorder_point: 50 },
        InventoryRecord { product_id: "PROD-D".into(), sku: "SKU-D-004".into(), warehouse: "WH-01".into(), quantity_on_hand: 20, reorder_point: 30 },
    ]
}

fn sample_customers() -> Vec<CustomerRecord> {
    vec![
        CustomerRecord { customer_id: "CUST-001".into(), name: "Alice Johnson".into(), tier: "gold".into(), lifetime_value: 5000.0, join_date: "2024-01-15".into() },
        CustomerRecord { customer_id: "CUST-002".into(), name: "Bob Smith".into(), tier: "silver".into(), lifetime_value: 2500.0, join_date: "2024-03-20".into() },
        CustomerRecord { customer_id: "CUST-003".into(), name: "Carol White".into(), tier: "premium".into(), lifetime_value: 15000.0, join_date: "2023-11-10".into() },
        CustomerRecord { customer_id: "CUST-004".into(), name: "David Brown".into(), tier: "standard".into(), lifetime_value: 500.0, join_date: "2025-01-05".into() },
        CustomerRecord { customer_id: "CUST-005".into(), name: "Eve Davis".into(), tier: "gold".into(), lifetime_value: 7500.0, join_date: "2024-06-12".into() },
    ]
}

// ============================================================================
// Extract Handlers (Parallel - No Dependencies)
// ============================================================================

/// Extracts sales records from simulated database. Returns raw records with summary stats.
pub fn extract_sales(_context: &Value) -> Result<Value, String> {
    let records = sample_sales();
    let total_amount: f64 = records.iter().map(|r| r.amount).sum();
    let total_quantity: i64 = records.iter().map(|r| r.quantity).sum();

    info!("Extracted {} sales records (total: ${:.2})", records.len(), total_amount);

    Ok(json!({
        "records": records,
        "record_count": records.len(),
        "total_amount": total_amount,
        "total_quantity": total_quantity,
        "source": "SalesDatabase",
        "extracted_at": chrono::Utc::now().to_rfc3339()
    }))
}

/// Extracts inventory records from simulated warehouse system.
pub fn extract_inventory(_context: &Value) -> Result<Value, String> {
    let records = sample_inventory();
    let total_on_hand: i64 = records.iter().map(|r| r.quantity_on_hand).sum();
    let warehouses: Vec<String> = records.iter()
        .map(|r| r.warehouse.clone())
        .collect::<std::collections::HashSet<_>>()
        .into_iter()
        .collect();

    info!("Extracted {} inventory records across {} warehouses", records.len(), warehouses.len());

    Ok(json!({
        "records": records,
        "record_count": records.len(),
        "total_quantity_on_hand": total_on_hand,
        "warehouses": warehouses,
        "source": "InventorySystem",
        "extracted_at": chrono::Utc::now().to_rfc3339()
    }))
}

/// Extracts customer records from simulated CRM.
pub fn extract_customers(_context: &Value) -> Result<Value, String> {
    let records = sample_customers();
    let total_ltv: f64 = records.iter().map(|r| r.lifetime_value).sum();
    let mut tier_counts: HashMap<String, i64> = HashMap::new();
    for r in &records {
        *tier_counts.entry(r.tier.clone()).or_insert(0) += 1;
    }

    info!("Extracted {} customer records (total LTV: ${:.2})", records.len(), total_ltv);

    Ok(json!({
        "records": records,
        "record_count": records.len(),
        "total_lifetime_value": total_ltv,
        "tier_breakdown": tier_counts,
        "source": "CRMSystem",
        "extracted_at": chrono::Utc::now().to_rfc3339()
    }))
}

// ============================================================================
// Transform Handlers
// ============================================================================

/// Transforms sales data into daily and product-level aggregations.
pub fn transform_sales(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let extract_result = dependency_results.get("extract_sales_data")
        .ok_or("Missing extract_sales_data dependency")?;

    let records: Vec<SalesRecord> = serde_json::from_value(
        extract_result.get("records").cloned().unwrap_or(json!([]))
    ).map_err(|e| format!("Failed to parse sales records: {}", e))?;

    // Group by product
    let mut product_groups: HashMap<String, (i64, f64, usize)> = HashMap::new();
    for record in &records {
        let entry = product_groups.entry(record.product_id.clone()).or_insert((0, 0.0, 0));
        entry.0 += record.quantity;
        entry.1 += record.amount;
        entry.2 += 1;
    }

    let mut product_sales: HashMap<String, Value> = HashMap::new();
    for (pid, (qty, rev, count)) in &product_groups {
        product_sales.insert(pid.clone(), json!({
            "total_quantity": qty,
            "total_revenue": (rev * 100.0).round() / 100.0,
            "order_count": count,
            "avg_order_value": ((rev / *count as f64) * 100.0).round() / 100.0
        }));
    }

    // Group by date
    let mut daily_groups: HashMap<String, (f64, usize)> = HashMap::new();
    for record in &records {
        let entry = daily_groups.entry(record.date.clone()).or_insert((0.0, 0));
        entry.0 += record.amount;
        entry.1 += 1;
    }

    let mut daily_sales: HashMap<String, Value> = HashMap::new();
    for (date, (total, count)) in &daily_groups {
        daily_sales.insert(date.clone(), json!({
            "total_amount": (total * 100.0).round() / 100.0,
            "order_count": count
        }));
    }

    let total_revenue: f64 = records.iter().map(|r| r.amount).sum();

    info!("Transformed {} sales records into {} product groups", records.len(), product_sales.len());

    Ok(json!({
        "record_count": records.len(),
        "product_sales": product_sales,
        "daily_sales": daily_sales,
        "total_revenue": (total_revenue * 100.0).round() / 100.0,
        "transformation_type": "sales_analytics"
    }))
}

/// Transforms inventory data into warehouse and product summaries with reorder alerts.
pub fn transform_inventory(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let extract_result = dependency_results.get("extract_inventory_data")
        .ok_or("Missing extract_inventory_data dependency")?;

    let records: Vec<InventoryRecord> = serde_json::from_value(
        extract_result.get("records").cloned().unwrap_or(json!([]))
    ).map_err(|e| format!("Failed to parse inventory records: {}", e))?;

    // Group by warehouse
    let mut warehouse_summary: HashMap<String, Value> = HashMap::new();
    let mut wh_groups: HashMap<String, Vec<&InventoryRecord>> = HashMap::new();
    for record in &records {
        wh_groups.entry(record.warehouse.clone()).or_default().push(record);
    }
    for (warehouse, wh_records) in &wh_groups {
        let total_qty: i64 = wh_records.iter().map(|r| r.quantity_on_hand).sum();
        let reorder_alerts = wh_records.iter().filter(|r| r.quantity_on_hand <= r.reorder_point).count();
        warehouse_summary.insert(warehouse.clone(), json!({
            "total_quantity": total_qty,
            "product_count": wh_records.len(),
            "reorder_alerts": reorder_alerts
        }));
    }

    // Group by product
    let mut product_inventory: HashMap<String, Value> = HashMap::new();
    let mut prod_groups: HashMap<String, Vec<&InventoryRecord>> = HashMap::new();
    for record in &records {
        prod_groups.entry(record.product_id.clone()).or_default().push(record);
    }
    let mut reorder_count = 0;
    for (product_id, prod_records) in &prod_groups {
        let total_qty: i64 = prod_records.iter().map(|r| r.quantity_on_hand).sum();
        let total_reorder: i64 = prod_records.iter().map(|r| r.reorder_point).sum();
        let needs_reorder = total_qty < total_reorder;
        if needs_reorder { reorder_count += 1; }
        product_inventory.insert(product_id.clone(), json!({
            "total_quantity": total_qty,
            "warehouse_count": prod_records.len(),
            "needs_reorder": needs_reorder
        }));
    }

    let total_on_hand: i64 = records.iter().map(|r| r.quantity_on_hand).sum();

    info!("Transformed {} inventory records, {} reorder alerts", records.len(), reorder_count);

    Ok(json!({
        "record_count": records.len(),
        "warehouse_summary": warehouse_summary,
        "product_inventory": product_inventory,
        "total_quantity_on_hand": total_on_hand,
        "reorder_alerts": reorder_count,
        "transformation_type": "inventory_analytics"
    }))
}

/// Transforms customer data into tier analysis and value segmentation.
pub fn transform_customers(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let extract_result = dependency_results.get("extract_customer_data")
        .ok_or("Missing extract_customer_data dependency")?;

    let records: Vec<CustomerRecord> = serde_json::from_value(
        extract_result.get("records").cloned().unwrap_or(json!([]))
    ).map_err(|e| format!("Failed to parse customer records: {}", e))?;

    // Group by tier
    let mut tier_analysis: HashMap<String, Value> = HashMap::new();
    let mut tier_groups: HashMap<String, Vec<&CustomerRecord>> = HashMap::new();
    for record in &records {
        tier_groups.entry(record.tier.clone()).or_default().push(record);
    }
    for (tier, tier_records) in &tier_groups {
        let total_ltv: f64 = tier_records.iter().map(|r| r.lifetime_value).sum();
        let count = tier_records.len();
        tier_analysis.insert(tier.clone(), json!({
            "customer_count": count,
            "total_lifetime_value": total_ltv,
            "avg_lifetime_value": (total_ltv / count as f64 * 100.0).round() / 100.0
        }));
    }

    // Value segmentation
    let high_value = records.iter().filter(|r| r.lifetime_value >= 10000.0).count();
    let medium_value = records.iter().filter(|r| r.lifetime_value >= 1000.0 && r.lifetime_value < 10000.0).count();
    let low_value = records.iter().filter(|r| r.lifetime_value < 1000.0).count();

    let total_ltv: f64 = records.iter().map(|r| r.lifetime_value).sum();
    let avg_value = if !records.is_empty() { total_ltv / records.len() as f64 } else { 0.0 };

    info!("Transformed {} customer records into {} tier groups", records.len(), tier_analysis.len());

    Ok(json!({
        "record_count": records.len(),
        "tier_analysis": tier_analysis,
        "value_segments": {
            "high_value": high_value,
            "medium_value": medium_value,
            "low_value": low_value
        },
        "total_lifetime_value": total_ltv,
        "avg_customer_value": (avg_value * 100.0).round() / 100.0,
        "transformation_type": "customer_analytics"
    }))
}

// ============================================================================
// Aggregate Metrics (DAG Convergence)
// ============================================================================

/// Combines metrics from all 3 transformed data sources into a unified view.
/// Calculates cross-source metrics like revenue per customer and inventory turnover.
pub fn aggregate_metrics(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let sales = dependency_results.get("transform_sales")
        .ok_or("Missing transform_sales dependency")?;
    let inventory = dependency_results.get("transform_inventory")
        .ok_or("Missing transform_inventory dependency")?;
    let customers = dependency_results.get("transform_customers")
        .ok_or("Missing transform_customers dependency")?;

    let total_revenue = sales.get("total_revenue").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let sales_count = sales.get("record_count").and_then(|v| v.as_i64()).unwrap_or(0);
    let total_inventory = inventory.get("total_quantity_on_hand").and_then(|v| v.as_i64()).unwrap_or(0);
    let reorder_alerts = inventory.get("reorder_alerts").and_then(|v| v.as_i64()).unwrap_or(0);
    let total_customers = customers.get("record_count").and_then(|v| v.as_i64()).unwrap_or(0);
    let total_ltv = customers.get("total_lifetime_value").and_then(|v| v.as_f64()).unwrap_or(0.0);

    let revenue_per_customer = if total_customers > 0 {
        (total_revenue / total_customers as f64 * 100.0).round() / 100.0
    } else { 0.0 };

    let inventory_turnover = if total_inventory > 0 {
        (total_revenue / total_inventory as f64 * 10000.0).round() / 10000.0
    } else { 0.0 };

    info!(
        "Aggregated: revenue=${:.2}, inventory={}, customers={}, rev/customer=${:.2}",
        total_revenue, total_inventory, total_customers, revenue_per_customer
    );

    Ok(json!({
        "total_revenue": total_revenue,
        "total_inventory_quantity": total_inventory,
        "total_customers": total_customers,
        "total_customer_lifetime_value": total_ltv,
        "sales_transactions": sales_count,
        "inventory_reorder_alerts": reorder_alerts,
        "revenue_per_customer": revenue_per_customer,
        "inventory_turnover_indicator": inventory_turnover,
        "aggregation_complete": true,
        "sources_included": 3
    }))
}

// ============================================================================
// Generate Insights
// ============================================================================

/// Generates actionable business insights from aggregated metrics.
/// Produces recommendations and a business health score (0-100).
pub fn generate_insights(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let metrics = dependency_results.get("aggregate_metrics")
        .ok_or("Missing aggregate_metrics dependency")?;

    let revenue = metrics.get("total_revenue").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let customers = metrics.get("total_customers").and_then(|v| v.as_i64()).unwrap_or(0);
    let revenue_per_customer = metrics.get("revenue_per_customer").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let inventory_alerts = metrics.get("inventory_reorder_alerts").and_then(|v| v.as_i64()).unwrap_or(0);
    let total_ltv = metrics.get("total_customer_lifetime_value").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let avg_ltv = if customers > 0 { total_ltv / customers as f64 } else { 0.0 };

    let mut insights = Vec::new();

    // Revenue insight
    let rev_recommendation = if revenue_per_customer < 500.0 {
        "Consider upselling strategies to increase average order value"
    } else {
        "Customer spend is healthy; focus on acquisition"
    };
    insights.push(json!({
        "category": "Revenue",
        "finding": format!("Total revenue ${:.2} across {} customers", revenue, customers),
        "metric": revenue_per_customer,
        "recommendation": rev_recommendation
    }));

    // Inventory insight
    if inventory_alerts > 0 {
        insights.push(json!({
            "category": "Inventory",
            "finding": format!("{} products below reorder threshold", inventory_alerts),
            "metric": inventory_alerts,
            "recommendation": "Review reorder points and place purchase orders immediately"
        }));
    } else {
        insights.push(json!({
            "category": "Inventory",
            "finding": "All products above reorder thresholds",
            "metric": 0,
            "recommendation": "Inventory levels are healthy; monitor seasonal demand"
        }));
    }

    // Customer value insight
    let ltv_recommendation = if avg_ltv > 3000.0 {
        "High-value customer base; invest in retention and loyalty programs"
    } else {
        "Increase customer engagement to improve lifetime value"
    };
    insights.push(json!({
        "category": "Customer Value",
        "finding": format!("Average customer lifetime value: ${:.2}", avg_ltv),
        "metric": (avg_ltv * 100.0).round() / 100.0,
        "recommendation": ltv_recommendation
    }));

    // Business health score (0-100)
    let mut score = 0;
    if revenue_per_customer > 500.0 { score += 40; }
    else if revenue_per_customer > 200.0 { score += 20; }
    if inventory_alerts == 0 { score += 30; }
    else if inventory_alerts < 3 { score += 15; }
    if avg_ltv > 3000.0 { score += 30; }
    else if avg_ltv > 1000.0 { score += 15; }

    let rating = match score {
        80..=100 => "Excellent",
        60..=79 => "Good",
        40..=59 => "Fair",
        _ => "Needs Improvement",
    };

    info!("Generated {} insights, health score: {}/100 ({})", insights.len(), score, rating);

    Ok(json!({
        "insights": insights,
        "health_score": {
            "score": score,
            "max_score": 100,
            "rating": rating
        },
        "total_metrics_analyzed": 10,
        "pipeline_complete": true,
        "generated_at": chrono::Utc::now().to_rfc3339()
    }))
}
