"""Data pipeline analytics business logic.

Pure functions that extract, transform, aggregate, and generate insights
from simulated data sources. No Tasker types — just plain dicts in,
typed models out.
"""

from __future__ import annotations

import hashlib
import random
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from tasker_core.errors import PermanentError, RetryableError

from .types import (
    PipelineAggregateMetricsResult,
    PipelineExtractCustomerResult,
    PipelineExtractInventoryResult,
    PipelineExtractSalesResult,
    PipelineGenerateInsightsResult,
    PipelineTransformCustomersResult,
    PipelineTransformInventoryResult,
    PipelineTransformSalesResult,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PRODUCT_CATEGORIES = ["electronics", "clothing", "food", "home", "sports"]
REGIONS = ["us-east", "us-west", "eu-central", "ap-southeast"]

TRAFFIC_SOURCES = ["organic", "paid_search", "social", "email", "direct", "referral"]
PAGES = ["/", "/products", "/pricing", "/about", "/checkout", "/signup"]

WAREHOUSES = ["WH-EAST-01", "WH-WEST-01", "WH-CENTRAL-01"]
INVENTORY_CATEGORIES = ["electronics", "clothing", "food", "home", "sports"]
STATUS_OPTIONS = ["in_stock", "low_stock", "out_of_stock", "on_order"]


# ---------------------------------------------------------------------------
# Extract functions
# ---------------------------------------------------------------------------


def extract_sales_data(
    source: str | None = None,
    date_range_start: str | None = None,
    date_range_end: str | None = None,
    granularity: str | None = None,
) -> PipelineExtractSalesResult:
    """Extract sales transaction records from simulated data source.

    Generates realistic sales records with timestamps, product IDs,
    quantities, and revenue figures for the specified date range.
    """
    source = source or "default"
    date_start = date_range_start or "2026-01-01"
    date_end = date_range_end or "2026-01-31"
    granularity = granularity or "daily"

    seed = int(hashlib.md5(f"sales:{source}:{date_start}".encode()).hexdigest()[:8], 16)
    rng = random.Random(seed)

    records: list[dict[str, Any]] = []
    num_records = 30 if granularity == "daily" else 120

    for i in range(num_records):
        record_id = f"sale_{uuid.uuid4().hex[:10]}"
        category = rng.choice(PRODUCT_CATEGORIES)
        region = rng.choice(REGIONS)
        quantity = rng.randint(1, 50)
        unit_price = round(rng.uniform(5.0, 500.0), 2)
        revenue = round(quantity * unit_price, 2)

        records.append(
            {
                "record_id": record_id,
                "category": category,
                "region": region,
                "quantity": quantity,
                "unit_price": unit_price,
                "revenue": revenue,
                "timestamp": (
                    datetime(2026, 1, 1, tzinfo=timezone.utc)
                    + timedelta(days=i % 31)
                ).isoformat(),
            }
        )

    total_revenue = round(sum(r["revenue"] for r in records), 2)
    total_quantity = sum(r["quantity"] for r in records)

    return PipelineExtractSalesResult(
        source="sales_database",
        record_count=len(records),
        records=records,
        total_amount=total_revenue,
        total_revenue=total_revenue,
        total_quantity=total_quantity,
        date_range={"start": date_start, "end": date_end},
        extracted_at=datetime.now(timezone.utc).isoformat(),
    )


def extract_inventory_data(
    source: str | None = None,
    date_range_start: str | None = None,
) -> PipelineExtractInventoryResult:
    """Extract web traffic analytics from simulated data source.

    Generates page view, session, and conversion records grouped by
    traffic source and landing page.
    """
    source = source or "default"
    date_start = date_range_start or "2026-01-01"

    seed = int(hashlib.md5(f"traffic:{source}:{date_start}".encode()).hexdigest()[:8], 16)
    rng = random.Random(seed)

    records: list[dict[str, Any]] = []
    num_records = 25

    for i in range(num_records):
        traffic_source = rng.choice(TRAFFIC_SOURCES)
        landing_page = rng.choice(PAGES)
        sessions = rng.randint(100, 10000)
        page_views = sessions * rng.randint(2, 8)
        bounce_rate = round(rng.uniform(0.15, 0.75), 3)
        avg_session_duration = round(rng.uniform(30.0, 600.0), 1)
        conversions = int(sessions * rng.uniform(0.01, 0.15))

        records.append(
            {
                "record_id": f"web_{uuid.uuid4().hex[:10]}",
                "traffic_source": traffic_source,
                "landing_page": landing_page,
                "sessions": sessions,
                "page_views": page_views,
                "bounce_rate": bounce_rate,
                "avg_session_duration_seconds": avg_session_duration,
                "conversions": conversions,
                "conversion_rate": round(conversions / sessions, 4) if sessions > 0 else 0.0,
                "date": (
                    datetime(2026, 1, 1, tzinfo=timezone.utc) + timedelta(days=i)
                ).strftime("%Y-%m-%d"),
            }
        )

    total_sessions = sum(r["sessions"] for r in records)
    total_conversions = sum(r["conversions"] for r in records)
    warehouses = list({r.get("landing_page", "/") for r in records})

    return PipelineExtractInventoryResult(
        source="web_analytics",
        record_count=len(records),
        records=records,
        total_quantity=total_sessions,
        total_sessions=total_sessions,
        total_conversions=total_conversions,
        overall_conversion_rate=(
            round(total_conversions / total_sessions, 4)
            if total_sessions > 0
            else 0.0
        ),
        warehouses=warehouses,
        products_tracked=len(records),
        extracted_at=datetime.now(timezone.utc).isoformat(),
    )


def extract_customer_data(
    source: str | None = None,
) -> PipelineExtractCustomerResult:
    """Extract inventory level data from simulated warehouse systems.

    Generates stock level records by SKU, warehouse, and category with
    reorder points and lead times.
    """
    source = source or "default"

    seed = int(hashlib.md5(f"inventory:{source}".encode()).hexdigest()[:8], 16)
    rng = random.Random(seed)

    records: list[dict[str, Any]] = []
    num_records = 20

    for i in range(num_records):
        sku = f"SKU-{rng.randint(10000, 99999)}"
        warehouse = rng.choice(WAREHOUSES)
        category = rng.choice(INVENTORY_CATEGORIES)
        current_stock = rng.randint(0, 500)
        reorder_point = rng.randint(10, 50)
        lead_time_days = rng.randint(3, 21)
        unit_cost = round(rng.uniform(2.0, 200.0), 2)

        if current_stock == 0:
            status = "out_of_stock"
        elif current_stock <= reorder_point:
            status = "low_stock"
        else:
            status = "in_stock"

        records.append(
            {
                "record_id": f"inv_{uuid.uuid4().hex[:10]}",
                "sku": sku,
                "warehouse": warehouse,
                "category": category,
                "current_stock": current_stock,
                "reorder_point": reorder_point,
                "lead_time_days": lead_time_days,
                "unit_cost": unit_cost,
                "inventory_value": round(current_stock * unit_cost, 2),
                "status": status,
            }
        )

    total_value = round(sum(r["inventory_value"] for r in records), 2)
    low_stock_count = sum(1 for r in records if r["status"] in ("low_stock", "out_of_stock"))

    # Source-aligned keys: total_customers, total_lifetime_value, tier_breakdown, avg_lifetime_value
    tier_breakdown: dict[str, int] = {}
    for record in records:
        cat = record["category"]
        tier_breakdown[cat] = tier_breakdown.get(cat, 0) + 1

    return PipelineExtractCustomerResult(
        source="warehouse_management",
        record_count=len(records),
        records=records,
        total_customers=len(records),
        total_lifetime_value=total_value,
        avg_lifetime_value=round(total_value / len(records), 2) if records else 0,
        tier_breakdown=tier_breakdown,
        total_inventory_value=total_value,
        low_stock_alerts=low_stock_count,
        extracted_at=datetime.now(timezone.utc).isoformat(),
    )


# ---------------------------------------------------------------------------
# Transform functions
# ---------------------------------------------------------------------------


def transform_sales(
    sales_data: PipelineExtractSalesResult,
) -> PipelineTransformSalesResult:
    """Transform raw sales data into aggregated category and region summaries.

    Groups sales records by category and region, computing totals and averages.
    """
    records = sales_data.records or []

    by_category: dict[str, dict[str, Any]] = {}
    by_region: dict[str, dict[str, Any]] = {}

    for record in records:
        cat = record["category"]
        region = record["region"]

        if cat not in by_category:
            by_category[cat] = {"revenue": 0.0, "quantity": 0, "transaction_count": 0}
        by_category[cat]["revenue"] = round(by_category[cat]["revenue"] + record["revenue"], 2)
        by_category[cat]["quantity"] += record["quantity"]
        by_category[cat]["transaction_count"] += 1

        if region not in by_region:
            by_region[region] = {"revenue": 0.0, "quantity": 0, "transaction_count": 0}
        by_region[region]["revenue"] = round(by_region[region]["revenue"] + record["revenue"], 2)
        by_region[region]["quantity"] += record["quantity"]
        by_region[region]["transaction_count"] += 1

    for summary in by_category.values():
        summary["avg_revenue"] = round(
            summary["revenue"] / summary["transaction_count"], 2
        ) if summary["transaction_count"] > 0 else 0.0

    for summary in by_region.values():
        summary["avg_revenue"] = round(
            summary["revenue"] / summary["transaction_count"], 2
        ) if summary["transaction_count"] > 0 else 0.0

    top_category = max(by_category, key=lambda k: by_category[k]["revenue"]) if by_category else None
    total_revenue = round(sum(r["revenue"] for r in records), 2)

    return PipelineTransformSalesResult(
        record_count=len(records),
        daily_sales=by_region,
        product_sales=by_category,
        total_revenue=total_revenue,
        by_category=by_category,
        by_region=by_region,
        top_category=top_category,
        total_categories=len(by_category),
        total_regions=len(by_region),
        records_processed=len(records),
        transformed_at=datetime.now(timezone.utc).isoformat(),
    )


def transform_inventory(
    traffic_data: PipelineExtractInventoryResult,
) -> PipelineTransformInventoryResult:
    """Transform raw web traffic data into source and page summaries.

    Groups web traffic by source and landing page, computes weighted
    bounce rates and total conversions.
    """
    records = traffic_data.records or []

    by_source: dict[str, dict[str, Any]] = {}
    by_page: dict[str, dict[str, Any]] = {}

    for record in records:
        src = record["traffic_source"]
        page = record["landing_page"]

        if src not in by_source:
            by_source[src] = {"sessions": 0, "conversions": 0, "total_bounce_weighted": 0.0}
        by_source[src]["sessions"] += record["sessions"]
        by_source[src]["conversions"] += record["conversions"]
        by_source[src]["total_bounce_weighted"] += record["bounce_rate"] * record["sessions"]

        if page not in by_page:
            by_page[page] = {"sessions": 0, "page_views": 0, "conversions": 0}
        by_page[page]["sessions"] += record["sessions"]
        by_page[page]["page_views"] += record["page_views"]
        by_page[page]["conversions"] += record["conversions"]

    for src_data in by_source.values():
        s = src_data["sessions"]
        src_data["conversion_rate"] = round(src_data["conversions"] / s, 4) if s > 0 else 0.0
        src_data["avg_bounce_rate"] = round(src_data["total_bounce_weighted"] / s, 4) if s > 0 else 0.0
        del src_data["total_bounce_weighted"]

    for page_data in by_page.values():
        s = page_data["sessions"]
        page_data["conversion_rate"] = round(page_data["conversions"] / s, 4) if s > 0 else 0.0
        page_data["pages_per_session"] = round(page_data["page_views"] / s, 2) if s > 0 else 0.0

    best_source = max(by_source, key=lambda k: by_source[k]["conversion_rate"]) if by_source else None
    total_sessions = sum(r["sessions"] for r in records)

    return PipelineTransformInventoryResult(
        record_count=len(records),
        warehouse_summary=by_source,
        product_inventory=by_page,
        total_quantity_on_hand=total_sessions,
        reorder_alerts=0,
        by_source=by_source,
        by_page=by_page,
        best_converting_source=best_source,
        total_sources=len(by_source),
        total_pages=len(by_page),
        records_processed=len(records),
        transformed_at=datetime.now(timezone.utc).isoformat(),
    )


def transform_customers(
    inventory_data: PipelineExtractCustomerResult,
) -> PipelineTransformCustomersResult:
    """Transform raw inventory data into warehouse and category summaries.

    Groups inventory by warehouse and category, identifies low-stock items,
    and calculates total inventory value distribution.
    """
    records = inventory_data.records or []

    by_warehouse: dict[str, dict[str, Any]] = {}
    by_category: dict[str, dict[str, Any]] = {}
    low_stock_items: list[dict[str, Any]] = []

    for record in records:
        wh = record["warehouse"]
        cat = record["category"]

        if wh not in by_warehouse:
            by_warehouse[wh] = {"total_stock": 0, "total_value": 0.0, "sku_count": 0}
        by_warehouse[wh]["total_stock"] += record["current_stock"]
        by_warehouse[wh]["total_value"] = round(
            by_warehouse[wh]["total_value"] + record["inventory_value"], 2
        )
        by_warehouse[wh]["sku_count"] += 1

        if cat not in by_category:
            by_category[cat] = {"total_stock": 0, "total_value": 0.0, "sku_count": 0}
        by_category[cat]["total_stock"] += record["current_stock"]
        by_category[cat]["total_value"] = round(
            by_category[cat]["total_value"] + record["inventory_value"], 2
        )
        by_category[cat]["sku_count"] += 1

        if record["status"] in ("low_stock", "out_of_stock"):
            low_stock_items.append(
                {
                    "sku": record["sku"],
                    "warehouse": wh,
                    "current_stock": record["current_stock"],
                    "reorder_point": record["reorder_point"],
                    "status": record["status"],
                }
            )

    total_value = round(sum(r.get("inventory_value", 0) for r in records), 2)

    return PipelineTransformCustomersResult(
        record_count=len(records),
        tier_analysis=by_category,
        value_segments=by_warehouse,
        total_lifetime_value=total_value,
        avg_customer_value=round(total_value / len(records), 2) if records else 0,
        by_warehouse=by_warehouse,
        by_category=by_category,
        low_stock_items=low_stock_items,
        low_stock_count=len(low_stock_items),
        total_skus=len(records),
        records_processed=len(records),
        transformed_at=datetime.now(timezone.utc).isoformat(),
    )


# ---------------------------------------------------------------------------
# Aggregate and insight functions
# ---------------------------------------------------------------------------


def aggregate_metrics(
    sales_transform: PipelineTransformSalesResult,
    traffic_transform: PipelineTransformInventoryResult,
    inventory_transform: PipelineTransformCustomersResult,
) -> PipelineAggregateMetricsResult:
    """Aggregate results from all three transform steps into unified metrics.

    Combines sales, web traffic, and inventory transforms into a single
    cross-domain metrics summary.
    """
    # Source-aligned reads from transform results
    total_revenue = sales_transform.total_revenue or 0
    sales_record_count = sales_transform.record_count or 0

    total_inventory = traffic_transform.total_quantity_on_hand or 0
    reorder_alerts = traffic_transform.reorder_alerts or 0

    total_customers = inventory_transform.record_count or 0
    total_ltv = inventory_transform.total_lifetime_value or 0

    # Cross-source metrics
    revenue_per_customer = round(total_revenue / total_customers, 2) if total_customers > 0 else 0
    inventory_turnover = round(total_revenue / total_inventory, 4) if total_inventory > 0 else 0

    total_records = (
        (sales_transform.records_processed or 0)
        + (traffic_transform.records_processed or 0)
        + (inventory_transform.records_processed or 0)
    )

    return PipelineAggregateMetricsResult(
        total_revenue=total_revenue,
        total_inventory_quantity=total_inventory,
        total_customers=total_customers,
        total_customer_lifetime_value=total_ltv,
        sales_transactions=sales_record_count,
        inventory_reorder_alerts=reorder_alerts,
        revenue_per_customer=revenue_per_customer,
        inventory_turnover_indicator=inventory_turnover,
        aggregation_complete=True,
        sources_included=3,
        sales_summary={
            "top_category": sales_transform.top_category,
            "categories": sales_transform.total_categories or 0,
            "regions": sales_transform.total_regions or 0,
        },
        traffic_summary={
            "best_source": traffic_transform.best_converting_source,
            "sources_analyzed": traffic_transform.total_sources or 0,
            "pages_analyzed": traffic_transform.total_pages or 0,
        },
        inventory_summary={
            "total_skus": inventory_transform.total_skus or 0,
            "low_stock_alerts": inventory_transform.low_stock_count or 0,
        },
        total_records_processed=total_records,
        data_sources=["sales", "web_traffic", "inventory"],
        aggregated_at=datetime.now(timezone.utc).isoformat(),
    )


def generate_insights(
    metrics: PipelineAggregateMetricsResult,
) -> PipelineGenerateInsightsResult:
    """Generate business insights and health score from aggregated metrics.

    Reads the aggregate_metrics result and produces actionable insights
    with a computed business health score (0-100).
    """
    insights: list[dict[str, Any]] = []
    health_score_value = 75  # baseline

    # Source-aligned reads from aggregate_metrics
    revenue = metrics.total_revenue or 0
    customers = metrics.total_customers or 0
    revenue_per_customer = metrics.revenue_per_customer or 0
    inventory_alerts = metrics.inventory_reorder_alerts or 0
    total_ltv = metrics.total_customer_lifetime_value or 0

    # Also read app-specific nested summaries if present
    sales_summary = metrics.sales_summary or {}
    traffic_summary = metrics.traffic_summary or {}
    inventory_summary = metrics.inventory_summary or {}

    if revenue > 0:
        recommendation = (
            "Consider upselling strategies"
            if revenue_per_customer < 500
            else "Customer spend is healthy"
        )
        insights.append(
            {
                "category": "Revenue",
                "finding": f"Total revenue of ${revenue} with {customers} customers",
                "metric": revenue_per_customer,
                "recommendation": recommendation,
            }
        )

    if sales_summary.get("top_category"):
        insights.append(
            {
                "category": "sales",
                "insight": f"Top performing category is '{sales_summary['top_category']}'",
                "priority": "info",
                "action": "Consider increasing marketing spend in this category",
            }
        )

    if traffic_summary.get("best_source"):
        insights.append(
            {
                "category": "marketing",
                "insight": f"Best converting traffic source is '{traffic_summary['best_source']}'",
                "priority": "high",
                "action": "Increase budget allocation for this channel",
            }
        )
        health_score_value += 5

    low_stock = inventory_alerts or inventory_summary.get("low_stock_alerts", 0)
    if low_stock > 5:
        insights.append(
            {
                "category": "Inventory",
                "finding": f"{low_stock} products need reordering",
                "metric": low_stock,
                "recommendation": "Review reorder points and place purchase orders",
            }
        )
        health_score_value -= 15
    elif low_stock > 0:
        insights.append(
            {
                "category": "Inventory",
                "finding": f"{low_stock} SKUs need attention",
                "metric": low_stock,
                "recommendation": "Review reorder schedules",
            }
        )
        health_score_value -= 5
    else:
        insights.append(
            {
                "category": "Inventory",
                "finding": "All products above reorder points",
                "metric": 0,
                "recommendation": "Inventory levels are healthy",
            }
        )

    # Customer insights
    avg_ltv = total_ltv / customers if customers > 0 else 0
    recommendation = (
        "Focus on retention programs" if avg_ltv > 3000 else "Increase customer engagement"
    )
    insights.append(
        {
            "category": "Customer Value",
            "finding": f"Average customer lifetime value: ${avg_ltv:.2f}",
            "metric": avg_ltv,
            "recommendation": recommendation,
        }
    )

    total_records = metrics.total_records_processed or 0
    if total_records > 50:
        health_score_value += 10
        insights.append(
            {
                "category": "data_quality",
                "insight": f"Strong data coverage: {total_records} records analyzed",
                "priority": "info",
                "action": "No action needed",
            }
        )

    health_score_value = max(0, min(100, health_score_value))

    # Source-aligned health_score as dict
    health_score = {
        "score": health_score_value,
        "max_score": 100,
        "rating": (
            "Excellent" if health_score_value >= 80
            else "Good" if health_score_value >= 60
            else "Fair" if health_score_value >= 40
            else "Needs Improvement"
        ),
    }

    return PipelineGenerateInsightsResult(
        insights=insights,
        health_score=health_score,
        total_metrics_analyzed=len(metrics.model_fields),
        pipeline_complete=True,
        insight_count=len(insights),
        health_status=health_score["rating"].lower().replace(" ", "_"),
        recommendations_count=sum(
            1 for i in insights if i.get("priority") in ("high", "critical")
        ),
        generated_at=datetime.now(timezone.utc).isoformat(),
    )
