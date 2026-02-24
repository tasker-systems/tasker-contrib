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

use crate::types::data_pipeline::*;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use tracing::info;

// ============================================================================
// Sample Data Types
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SalesRecord {
    date: String,
    product: String,
    category: String,
    region: String,
    quantity: i64,
    unit_price: f64,
    total: f64,
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
        SalesRecord { date: "2025-11-01".into(), product: "Widget A".into(), category: "widgets".into(), region: "north".into(), quantity: 5, unit_price: 99.99, total: 499.95 },
        SalesRecord { date: "2025-11-05".into(), product: "Widget B".into(), category: "widgets".into(), region: "south".into(), quantity: 3, unit_price: 99.99, total: 299.97 },
        SalesRecord { date: "2025-11-10".into(), product: "Widget A".into(), category: "widgets".into(), region: "north".into(), quantity: 2, unit_price: 99.99, total: 199.98 },
        SalesRecord { date: "2025-11-15".into(), product: "Gadget X".into(), category: "gadgets".into(), region: "east".into(), quantity: 10, unit_price: 149.99, total: 1499.90 },
        SalesRecord { date: "2025-11-18".into(), product: "Widget B".into(), category: "widgets".into(), region: "west".into(), quantity: 7, unit_price: 99.99, total: 699.93 },
        SalesRecord { date: "2025-11-22".into(), product: "Widget A".into(), category: "widgets".into(), region: "north".into(), quantity: 4, unit_price: 99.99, total: 399.96 },
        SalesRecord { date: "2025-11-25".into(), product: "Gadget Y".into(), category: "gadgets".into(), region: "east".into(), quantity: 1, unit_price: 249.99, total: 249.99 },
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
        CustomerRecord { customer_id: "CUST-002".into(), name: "Bob Smith".into(), tier: "standard".into(), lifetime_value: 2500.0, join_date: "2024-03-20".into() },
        CustomerRecord { customer_id: "CUST-003".into(), name: "Carol White".into(), tier: "premium".into(), lifetime_value: 15000.0, join_date: "2023-11-10".into() },
        CustomerRecord { customer_id: "CUST-004".into(), name: "David Brown".into(), tier: "standard".into(), lifetime_value: 500.0, join_date: "2025-01-05".into() },
        CustomerRecord { customer_id: "CUST-005".into(), name: "Eve Davis".into(), tier: "gold".into(), lifetime_value: 7500.0, join_date: "2024-06-12".into() },
    ]
}

// ============================================================================
// Extract Handlers (Parallel - No Dependencies)
// ============================================================================

/// Extracts sales records from simulated database.
pub fn extract_sales(_context: &Value) -> Result<Value, String> {
    let raw = sample_sales();
    let total_revenue: f64 = raw.iter().map(|r| r.total).sum();
    let total_quantity: i64 = raw.iter().map(|r| r.quantity).sum();

    let records: Vec<ExtractSalesDataResultRecords> = raw
        .iter()
        .map(|r| ExtractSalesDataResultRecords {
            date: r.date.clone(),
            product: r.product.clone(),
            category: r.category.clone(),
            region: r.region.clone(),
            quantity: r.quantity,
            unit_price: r.unit_price,
            total: r.total,
        })
        .collect();

    info!(
        "Extracted {} sales records (total: ${:.2})",
        records.len(),
        total_revenue
    );

    let result = ExtractSalesDataResult {
        source: "SalesDatabase".to_string(),
        record_count: records.len() as i64,
        records,
        total_revenue,
        total_quantity,
        extracted_at: chrono::Utc::now().to_rfc3339(),
        date_range: ExtractSalesDataResultDateRange {
            start_date: "2025-11-01".to_string(),
            end_date: "2025-11-25".to_string(),
        },
        total_amount: Some(total_revenue),
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

/// Extracts inventory records from simulated warehouse system.
pub fn extract_inventory(_context: &Value) -> Result<Value, String> {
    let raw = sample_inventory();
    let total_on_hand: i64 = raw.iter().map(|r| r.quantity_on_hand).sum();
    let warehouses: Vec<String> = raw
        .iter()
        .map(|r| r.warehouse.clone())
        .collect::<std::collections::HashSet<_>>()
        .into_iter()
        .collect();
    let products_tracked = raw
        .iter()
        .map(|r| r.product_id.clone())
        .collect::<std::collections::HashSet<_>>()
        .len();

    let records: Vec<Value> = raw
        .iter()
        .map(|r| serde_json::to_value(r).unwrap_or_default())
        .collect();

    info!(
        "Extracted {} inventory records across {} warehouses",
        records.len(),
        warehouses.len()
    );

    let result = ExtractInventoryDataResult {
        source: "InventorySystem".to_string(),
        record_count: records.len() as i64,
        records,
        extracted_at: chrono::Utc::now().to_rfc3339(),
        warehouses: Some(warehouses),
        products_tracked: Some(products_tracked as i64),
        total_quantity: Some(total_on_hand),
        total_sessions: None,
        total_conversions: None,
        overall_conversion_rate: None,
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

/// Extracts customer records from simulated CRM.
pub fn extract_customers(_context: &Value) -> Result<Value, String> {
    let raw = sample_customers();
    let total_ltv: f64 = raw.iter().map(|r| r.lifetime_value).sum();
    let mut tier_counts: HashMap<String, i64> = HashMap::new();
    for r in &raw {
        *tier_counts.entry(r.tier.clone()).or_insert(0) += 1;
    }

    let records: Vec<Value> = raw
        .iter()
        .map(|r| serde_json::to_value(r).unwrap_or_default())
        .collect();

    info!(
        "Extracted {} customer records (total LTV: ${:.2})",
        records.len(),
        total_ltv
    );

    let result = ExtractCustomerDataResult {
        source: "CRMSystem".to_string(),
        record_count: records.len() as i64,
        records,
        extracted_at: chrono::Utc::now().to_rfc3339(),
        total_lifetime_value: Some(total_ltv),
        total_customers: Some(raw.len() as i64),
        avg_lifetime_value: Some((total_ltv / raw.len() as f64 * 100.0).round() / 100.0),
        tier_breakdown: Some(ExtractCustomerDataResultTierBreakdown {
            standard: tier_counts.get("standard").copied(),
            premium: tier_counts.get("premium").copied(),
            gold: tier_counts.get("gold").copied(),
        }),
        low_stock_alerts: None,
        total_inventory_value: None,
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Transform Handlers
// ============================================================================

/// Transforms sales data into daily and product-level aggregations.
pub fn transform_sales(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let extract: ExtractSalesDataResult = dependency_results
        .get("extract_sales_data")
        .ok_or("Missing extract_sales_data dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize sales extract result: {}", e))
        })?;

    // Convert typed records back to SalesRecord for aggregation logic
    let records: Vec<SalesRecord> = extract
        .records
        .iter()
        .map(|r| SalesRecord {
            date: r.date.clone(),
            product: r.product.clone(),
            category: r.category.clone(),
            region: r.region.clone(),
            quantity: r.quantity,
            unit_price: r.unit_price,
            total: r.total,
        })
        .collect();

    // Group by product
    let mut product_groups: HashMap<String, (i64, f64, usize)> = HashMap::new();
    for record in &records {
        let entry = product_groups
            .entry(record.product.clone())
            .or_insert((0, 0.0, 0));
        entry.0 += record.quantity;
        entry.1 += record.total;
        entry.2 += 1;
    }

    let mut product_sales: HashMap<String, Value> = HashMap::new();
    for (pid, (qty, rev, count)) in &product_groups {
        product_sales.insert(
            pid.clone(),
            json!({
                "total_quantity": qty,
                "total_revenue": (rev * 100.0).round() / 100.0,
                "order_count": count,
                "avg_order_value": ((rev / *count as f64) * 100.0).round() / 100.0
            }),
        );
    }

    // Group by category
    let mut category_groups: HashMap<String, f64> = HashMap::new();
    for record in &records {
        *category_groups
            .entry(record.category.clone())
            .or_insert(0.0) += record.total;
    }
    let top_category = category_groups
        .iter()
        .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
        .map(|(k, _)| k.clone());

    // Group by region
    let mut region_groups: HashMap<String, f64> = HashMap::new();
    for record in &records {
        *region_groups.entry(record.region.clone()).or_insert(0.0) += record.total;
    }

    // Group by date
    let mut daily_groups: HashMap<String, (f64, usize)> = HashMap::new();
    for record in &records {
        let entry = daily_groups.entry(record.date.clone()).or_insert((0.0, 0));
        entry.0 += record.total;
        entry.1 += 1;
    }

    let mut daily_sales: HashMap<String, Value> = HashMap::new();
    for (date, (total, count)) in &daily_groups {
        daily_sales.insert(
            date.clone(),
            json!({
                "total_amount": (total * 100.0).round() / 100.0,
                "order_count": count
            }),
        );
    }

    let total_revenue: f64 = records.iter().map(|r| r.total).sum();

    let total_categories = category_groups.len() as i64;
    let total_regions = region_groups.len() as i64;

    info!(
        "Transformed {} sales records into {} product groups",
        records.len(),
        product_sales.len()
    );

    let result = TransformSalesResult {
        records_processed: records.len() as i64,
        record_count: records.len() as i64,
        total_revenue: (total_revenue * 100.0).round() / 100.0,
        transformed_at: chrono::Utc::now().to_rfc3339(),
        by_category: Some(serde_json::to_value(category_groups).unwrap_or_default()),
        by_region: Some(serde_json::to_value(region_groups).unwrap_or_default()),
        daily_sales: Some(serde_json::to_value(daily_sales).unwrap_or_default()),
        product_sales: Some(serde_json::to_value(product_sales).unwrap_or_default()),
        top_category,
        total_categories: Some(total_categories),
        total_regions: Some(total_regions),
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

/// Transforms inventory data into warehouse and product summaries with reorder alerts.
pub fn transform_inventory(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let extract: ExtractInventoryDataResult = dependency_results
        .get("extract_inventory_data")
        .ok_or("Missing extract_inventory_data dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize inventory extract result: {}", e))
        })?;

    let records: Vec<InventoryRecord> = extract
        .records
        .iter()
        .filter_map(|v| serde_json::from_value(v.clone()).ok())
        .collect();

    // Group by warehouse
    let mut wh_groups: HashMap<String, Vec<&InventoryRecord>> = HashMap::new();
    for record in &records {
        wh_groups
            .entry(record.warehouse.clone())
            .or_default()
            .push(record);
    }
    let mut warehouse_summary: HashMap<String, Value> = HashMap::new();
    for (warehouse, wh_records) in &wh_groups {
        let total_qty: i64 = wh_records.iter().map(|r| r.quantity_on_hand).sum();
        let reorder_alerts = wh_records
            .iter()
            .filter(|r| r.quantity_on_hand <= r.reorder_point)
            .count();
        warehouse_summary.insert(
            warehouse.clone(),
            json!({
                "total_quantity": total_qty,
                "product_count": wh_records.len(),
                "reorder_alerts": reorder_alerts
            }),
        );
    }

    // Group by product
    let mut prod_groups: HashMap<String, Vec<&InventoryRecord>> = HashMap::new();
    for record in &records {
        prod_groups
            .entry(record.product_id.clone())
            .or_default()
            .push(record);
    }
    let mut product_inventory: HashMap<String, Value> = HashMap::new();
    let mut reorder_count = 0;
    for (product_id, prod_records) in &prod_groups {
        let total_qty: i64 = prod_records.iter().map(|r| r.quantity_on_hand).sum();
        let total_reorder: i64 = prod_records.iter().map(|r| r.reorder_point).sum();
        let needs_reorder = total_qty < total_reorder;
        if needs_reorder {
            reorder_count += 1;
        }
        product_inventory.insert(
            product_id.clone(),
            json!({
                "total_quantity": total_qty,
                "warehouse_count": prod_records.len(),
                "needs_reorder": needs_reorder
            }),
        );
    }

    let total_on_hand: i64 = records.iter().map(|r| r.quantity_on_hand).sum();

    info!(
        "Transformed {} inventory records, {} reorder alerts",
        records.len(),
        reorder_count
    );

    let result = TransformInventoryResult {
        records_processed: records.len() as i64,
        record_count: records.len() as i64,
        transformed_at: chrono::Utc::now().to_rfc3339(),
        warehouse_summary: Some(serde_json::to_value(warehouse_summary).unwrap_or_default()),
        product_inventory: Some(serde_json::to_value(product_inventory).unwrap_or_default()),
        total_quantity_on_hand: Some(total_on_hand),
        reorder_alerts: Some(reorder_count),
        by_source: None,
        by_page: None,
        best_converting_source: None,
        total_sources: None,
        total_pages: None,
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

/// Transforms customer data into tier analysis and value segmentation.
pub fn transform_customers(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let extract: ExtractCustomerDataResult = dependency_results
        .get("extract_customer_data")
        .ok_or("Missing extract_customer_data dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize customer extract result: {}", e))
        })?;

    let records: Vec<CustomerRecord> = extract
        .records
        .iter()
        .filter_map(|v| serde_json::from_value(v.clone()).ok())
        .collect();

    // Group by tier
    let mut tier_groups: HashMap<String, Vec<&CustomerRecord>> = HashMap::new();
    for record in &records {
        tier_groups
            .entry(record.tier.clone())
            .or_default()
            .push(record);
    }
    let mut tier_analysis: HashMap<String, Value> = HashMap::new();
    for (tier, tier_records) in &tier_groups {
        let total_ltv: f64 = tier_records.iter().map(|r| r.lifetime_value).sum();
        let count = tier_records.len();
        tier_analysis.insert(
            tier.clone(),
            json!({
                "customer_count": count,
                "total_lifetime_value": total_ltv,
                "avg_lifetime_value": (total_ltv / count as f64 * 100.0).round() / 100.0
            }),
        );
    }

    // Value segmentation
    let high_value = records
        .iter()
        .filter(|r| r.lifetime_value >= 10000.0)
        .count();
    let medium_value = records
        .iter()
        .filter(|r| r.lifetime_value >= 1000.0 && r.lifetime_value < 10000.0)
        .count();
    let low_value = records
        .iter()
        .filter(|r| r.lifetime_value < 1000.0)
        .count();

    let total_ltv: f64 = records.iter().map(|r| r.lifetime_value).sum();
    let avg_value = if !records.is_empty() {
        total_ltv / records.len() as f64
    } else {
        0.0
    };

    info!(
        "Transformed {} customer records into {} tier groups",
        records.len(),
        tier_analysis.len()
    );

    let result = TransformCustomersResult {
        records_processed: records.len() as i64,
        record_count: records.len() as i64,
        transformed_at: chrono::Utc::now().to_rfc3339(),
        tier_analysis: Some(serde_json::to_value(tier_analysis).unwrap_or_default()),
        value_segments: Some(json!({
            "high_value": high_value,
            "medium_value": medium_value,
            "low_value": low_value
        })),
        total_lifetime_value: Some(total_ltv),
        avg_customer_value: Some((avg_value * 100.0).round() / 100.0),
        by_category: None,
        by_warehouse: None,
        low_stock_count: None,
        low_stock_items: None,
        total_skus: None,
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Aggregate Metrics (DAG Convergence)
// ============================================================================

/// Combines metrics from all 3 transformed data sources into a unified view.
pub fn aggregate_metrics(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let sales: TransformSalesResult = dependency_results
        .get("transform_sales")
        .ok_or("Missing transform_sales dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize sales transform result: {}", e))
        })?;

    let inventory: TransformInventoryResult = dependency_results
        .get("transform_inventory")
        .ok_or("Missing transform_inventory dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize inventory transform result: {}", e))
        })?;

    let customers: TransformCustomersResult = dependency_results
        .get("transform_customers")
        .ok_or("Missing transform_customers dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize customer transform result: {}", e))
        })?;

    let total_inventory = inventory.total_quantity_on_hand.unwrap_or(0);
    let reorder_alerts = inventory.reorder_alerts.unwrap_or(0);
    let total_customers = customers.record_count;
    let total_ltv = customers.total_lifetime_value.unwrap_or(0.0);

    let revenue_per_customer = if total_customers > 0 {
        (sales.total_revenue / total_customers as f64 * 100.0).round() / 100.0
    } else {
        0.0
    };

    let inventory_turnover = if total_inventory > 0 {
        (sales.total_revenue / total_inventory as f64 * 10000.0).round() / 10000.0
    } else {
        0.0
    };

    let total_records = sales.record_count + inventory.record_count + total_customers;

    info!(
        "Aggregated: revenue=${:.2}, inventory={}, customers={}, rev/customer=${:.2}",
        sales.total_revenue, total_inventory, total_customers, revenue_per_customer
    );

    let result = AggregateMetricsResult {
        total_records_processed: total_records,
        sources_included: 3,
        aggregated_at: chrono::Utc::now().to_rfc3339(),
        data_sources: vec![
            "sales".to_string(),
            "inventory".to_string(),
            "customers".to_string(),
        ],
        aggregation_complete: true,
        total_revenue: Some(sales.total_revenue),
        total_customers: Some(total_customers),
        total_customer_lifetime_value: Some(total_ltv),
        sales_transactions: Some(sales.record_count),
        total_inventory_quantity: Some(total_inventory),
        inventory_reorder_alerts: Some(reorder_alerts),
        revenue_per_customer: Some(revenue_per_customer),
        inventory_turnover_indicator: Some(inventory_turnover),
        sales_summary: sales.by_category,
        inventory_summary: inventory.warehouse_summary,
        traffic_summary: None,
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}

// ============================================================================
// Generate Insights
// ============================================================================

/// Generates actionable business insights from aggregated metrics.
pub fn generate_insights(dependency_results: &HashMap<String, Value>) -> Result<Value, String> {
    let metrics: AggregateMetricsResult = dependency_results
        .get("aggregate_metrics")
        .ok_or("Missing aggregate_metrics dependency".to_string())
        .and_then(|v| {
            serde_json::from_value(v.clone())
                .map_err(|e| format!("Failed to deserialize aggregate result: {}", e))
        })?;

    let revenue = metrics.total_revenue.unwrap_or(0.0);
    let customers = metrics.total_customers.unwrap_or(0);
    let revenue_per_customer = metrics.revenue_per_customer.unwrap_or(0.0);
    let inventory_alerts = metrics.inventory_reorder_alerts.unwrap_or(0);
    let total_ltv = metrics.total_customer_lifetime_value.unwrap_or(0.0);
    let avg_ltv = if customers > 0 {
        total_ltv / customers as f64
    } else {
        0.0
    };

    let mut insights = Vec::new();

    // Revenue insight
    let rev_recommendation = if revenue_per_customer < 500.0 {
        "Consider upselling strategies to increase average order value"
    } else {
        "Customer spend is healthy; focus on acquisition"
    };
    insights.push(GenerateInsightsResultInsights {
        r#type: "trend".to_string(),
        severity: "info".to_string(),
        message: format!(
            "Total revenue ${:.2} across {} customers",
            revenue, customers
        ),
        metric: format!("{:.2}", revenue_per_customer),
        recommendation: rev_recommendation.to_string(),
    });

    // Inventory insight
    if inventory_alerts > 0 {
        insights.push(GenerateInsightsResultInsights {
            r#type: "alert".to_string(),
            severity: "warning".to_string(),
            message: format!("{} products below reorder threshold", inventory_alerts),
            metric: format!("{}", inventory_alerts),
            recommendation:
                "Review reorder points and place purchase orders immediately".to_string(),
        });
    } else {
        insights.push(GenerateInsightsResultInsights {
            r#type: "status".to_string(),
            severity: "info".to_string(),
            message: "All products above reorder thresholds".to_string(),
            metric: "0".to_string(),
            recommendation: "Inventory levels are healthy; monitor seasonal demand".to_string(),
        });
    }

    // Customer value insight
    let ltv_recommendation = if avg_ltv > 3000.0 {
        "High-value customer base; invest in retention and loyalty programs"
    } else {
        "Increase customer engagement to improve lifetime value"
    };
    insights.push(GenerateInsightsResultInsights {
        r#type: "trend".to_string(),
        severity: "info".to_string(),
        message: format!("Average customer lifetime value: ${:.2}", avg_ltv),
        metric: format!("{:.2}", (avg_ltv * 100.0).round() / 100.0),
        recommendation: ltv_recommendation.to_string(),
    });

    // Business health score (0-100)
    let mut score: i64 = 0;
    if revenue_per_customer > 500.0 {
        score += 40;
    } else if revenue_per_customer > 200.0 {
        score += 20;
    }
    if inventory_alerts == 0 {
        score += 30;
    } else if inventory_alerts < 3 {
        score += 15;
    }
    if avg_ltv > 3000.0 {
        score += 30;
    } else if avg_ltv > 1000.0 {
        score += 15;
    }

    let rating = match score {
        80..=100 => "Excellent",
        60..=79 => "Good",
        40..=59 => "Fair",
        _ => "Needs Improvement",
    };

    let recommendations_count = insights.len() as i64;

    info!(
        "Generated {} insights, health score: {}/100 ({})",
        insights.len(),
        score,
        rating
    );

    let result = GenerateInsightsResult {
        insight_count: insights.len() as i64,
        recommendations_count,
        total_metrics_analyzed: 10,
        generated_at: chrono::Utc::now().to_rfc3339(),
        pipeline_complete: true,
        health_score: Some(GenerateInsightsResultHealthScore {
            score,
            max_score: 100,
            rating: rating.to_string(),
            details: Some(format!(
                "Revenue: {}/40, Inventory: {}/30, Customer: {}/30",
                if revenue_per_customer > 500.0 {
                    40
                } else if revenue_per_customer > 200.0 {
                    20
                } else {
                    0
                },
                if inventory_alerts == 0 {
                    30
                } else if inventory_alerts < 3 {
                    15
                } else {
                    0
                },
                if avg_ltv > 3000.0 {
                    30
                } else if avg_ltv > 1000.0 {
                    15
                } else {
                    0
                }
            )),
        }),
        health_status: Some(rating.to_string()),
        insights: Some(insights),
    };

    serde_json::to_value(result).map_err(|e| format!("Failed to serialize result: {}", e))
}
