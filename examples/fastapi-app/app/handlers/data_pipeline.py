"""Data pipeline analytics step handlers.

8 steps forming a DAG pattern with 3 parallel extract branches:
  extract_sales_data    ─┐
  extract_web_traffic   ─┤─> transform_sales    ─┐
  extract_inventory     ─┘   transform_traffic   ─┤─> aggregate_metrics -> generate_insights
                              transform_inventory ─┘

Each extract handler generates sample data records. Transform handlers
aggregate and group their respective data. The aggregate step combines
all transforms, and the insights step produces final analysis.
"""

from __future__ import annotations

import hashlib
import random
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from tasker_core import ErrorType, StepContext, StepHandler, StepHandlerResult


class ExtractSalesDataHandler(StepHandler):
    """Extract sales transaction records from simulated data source.

    Generates realistic sales records with timestamps, product IDs,
    quantities, and revenue figures for the specified date range.
    """

    handler_name = "extract_sales_data"
    handler_version = "1.0.0"

    PRODUCT_CATEGORIES = ["electronics", "clothing", "food", "home", "sports"]
    REGIONS = ["us-east", "us-west", "eu-central", "ap-southeast"]

    def call(self, context: StepContext) -> StepHandlerResult:
        source = context.get_input("source") or "default"
        date_start = context.get_input("date_range_start") or "2026-01-01"
        date_end = context.get_input("date_range_end") or "2026-01-31"
        granularity = context.get_input("granularity") or "daily"

        seed = int(hashlib.md5(f"sales:{source}:{date_start}".encode()).hexdigest()[:8], 16)
        rng = random.Random(seed)

        records: list[dict[str, Any]] = []
        num_records = 30 if granularity == "daily" else 120

        for i in range(num_records):
            record_id = f"sale_{uuid.uuid4().hex[:10]}"
            category = rng.choice(self.PRODUCT_CATEGORIES)
            region = rng.choice(self.REGIONS)
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

        return StepHandlerResult.success(
            result={
                "source": "sales_database",
                "record_count": len(records),
                "records": records,
                "total_revenue": total_revenue,
                "total_quantity": total_quantity,
                "date_range": {"start": date_start, "end": date_end},
                "extracted_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"granularity": granularity, "source": source},
        )


class ExtractWebTrafficHandler(StepHandler):
    """Extract web traffic analytics from simulated data source.

    Generates page view, session, and conversion records grouped by
    traffic source and landing page.
    """

    handler_name = "extract_web_traffic"
    handler_version = "1.0.0"

    TRAFFIC_SOURCES = ["organic", "paid_search", "social", "email", "direct", "referral"]
    PAGES = ["/", "/products", "/pricing", "/about", "/checkout", "/signup"]

    def call(self, context: StepContext) -> StepHandlerResult:
        source = context.get_input("source") or "default"
        date_start = context.get_input("date_range_start") or "2026-01-01"

        seed = int(hashlib.md5(f"traffic:{source}:{date_start}".encode()).hexdigest()[:8], 16)
        rng = random.Random(seed)

        records: list[dict[str, Any]] = []
        num_records = 25

        for i in range(num_records):
            traffic_source = rng.choice(self.TRAFFIC_SOURCES)
            landing_page = rng.choice(self.PAGES)
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

        return StepHandlerResult.success(
            result={
                "source": "web_analytics",
                "record_count": len(records),
                "records": records,
                "total_sessions": total_sessions,
                "total_conversions": total_conversions,
                "overall_conversion_rate": (
                    round(total_conversions / total_sessions, 4)
                    if total_sessions > 0
                    else 0.0
                ),
                "extracted_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"analytics_platform": "simulated"},
        )


class ExtractInventoryHandler(StepHandler):
    """Extract inventory level data from simulated warehouse systems.

    Generates stock level records by SKU, warehouse, and category with
    reorder points and lead times.
    """

    handler_name = "extract_inventory"
    handler_version = "1.0.0"

    WAREHOUSES = ["WH-EAST-01", "WH-WEST-01", "WH-CENTRAL-01"]
    CATEGORIES = ["electronics", "clothing", "food", "home", "sports"]
    STATUS_OPTIONS = ["in_stock", "low_stock", "out_of_stock", "on_order"]

    def call(self, context: StepContext) -> StepHandlerResult:
        source = context.get_input("source") or "default"

        seed = int(hashlib.md5(f"inventory:{source}".encode()).hexdigest()[:8], 16)
        rng = random.Random(seed)

        records: list[dict[str, Any]] = []
        num_records = 20

        for i in range(num_records):
            sku = f"SKU-{rng.randint(10000, 99999)}"
            warehouse = rng.choice(self.WAREHOUSES)
            category = rng.choice(self.CATEGORIES)
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

        return StepHandlerResult.success(
            result={
                "source": "warehouse_management",
                "record_count": len(records),
                "records": records,
                "total_inventory_value": total_value,
                "low_stock_alerts": low_stock_count,
                "extracted_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"warehouses_scanned": len(self.WAREHOUSES)},
        )


class TransformSalesDataHandler(StepHandler):
    """Transform raw sales data into aggregated category and region summaries.

    Groups sales records by category and region, computing totals and averages.
    """

    handler_name = "transform_sales_data"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        sales_data = context.get_dependency_result("extract_sales_data")
        if sales_data is None:
            return StepHandlerResult.failure(
                message="Missing extract_sales_data dependency",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        records = sales_data.get("records", [])

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

        return StepHandlerResult.success(
            result={
                "by_category": by_category,
                "by_region": by_region,
                "top_category": top_category,
                "total_categories": len(by_category),
                "total_regions": len(by_region),
                "records_processed": len(records),
                "transformed_at": datetime.now(timezone.utc).isoformat(),
            },
        )


class TransformWebTrafficHandler(StepHandler):
    """Transform raw web traffic data into source and page summaries.

    Groups web traffic by source and landing page, computes weighted
    bounce rates and total conversions.
    """

    handler_name = "transform_web_traffic"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        traffic_data = context.get_dependency_result("extract_web_traffic")
        if traffic_data is None:
            return StepHandlerResult.failure(
                message="Missing extract_web_traffic dependency",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        records = traffic_data.get("records", [])

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

        return StepHandlerResult.success(
            result={
                "by_source": by_source,
                "by_page": by_page,
                "best_converting_source": best_source,
                "total_sources": len(by_source),
                "total_pages": len(by_page),
                "records_processed": len(records),
                "transformed_at": datetime.now(timezone.utc).isoformat(),
            },
        )


class TransformInventoryHandler(StepHandler):
    """Transform raw inventory data into warehouse and category summaries.

    Groups inventory by warehouse and category, identifies low-stock items,
    and calculates total inventory value distribution.
    """

    handler_name = "transform_inventory"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        inventory_data = context.get_dependency_result("extract_inventory")
        if inventory_data is None:
            return StepHandlerResult.failure(
                message="Missing extract_inventory dependency",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        records = inventory_data.get("records", [])

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

        return StepHandlerResult.success(
            result={
                "by_warehouse": by_warehouse,
                "by_category": by_category,
                "low_stock_items": low_stock_items,
                "low_stock_count": len(low_stock_items),
                "total_skus": len(records),
                "records_processed": len(records),
                "transformed_at": datetime.now(timezone.utc).isoformat(),
            },
        )


class AggregateMetricsHandler(StepHandler):
    """Aggregate results from all three transform steps into unified metrics.

    Combines sales, web traffic, and inventory transforms into a single
    cross-domain metrics summary.
    """

    handler_name = "aggregate_metrics"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        sales_transform = context.get_dependency_result("transform_sales_data")
        traffic_transform = context.get_dependency_result("transform_web_traffic")
        inventory_transform = context.get_dependency_result("transform_inventory")

        if not all([sales_transform, traffic_transform, inventory_transform]):
            return StepHandlerResult.failure(
                message="Missing one or more transform dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        total_records = (
            sales_transform.get("records_processed", 0)
            + traffic_transform.get("records_processed", 0)
            + inventory_transform.get("records_processed", 0)
        )

        return StepHandlerResult.success(
            result={
                "sales_summary": {
                    "top_category": sales_transform.get("top_category"),
                    "categories": sales_transform.get("total_categories", 0),
                    "regions": sales_transform.get("total_regions", 0),
                },
                "traffic_summary": {
                    "best_source": traffic_transform.get("best_converting_source"),
                    "sources_analyzed": traffic_transform.get("total_sources", 0),
                    "pages_analyzed": traffic_transform.get("total_pages", 0),
                },
                "inventory_summary": {
                    "total_skus": inventory_transform.get("total_skus", 0),
                    "low_stock_alerts": inventory_transform.get("low_stock_count", 0),
                },
                "total_records_processed": total_records,
                "data_sources": ["sales", "web_traffic", "inventory"],
                "aggregated_at": datetime.now(timezone.utc).isoformat(),
            },
        )


class GenerateInsightsHandler(StepHandler):
    """Generate business insights and health score from aggregated metrics.

    Reads the aggregate_metrics result and produces actionable insights
    with a computed business health score (0-100).
    """

    handler_name = "generate_insights"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        metrics = context.get_dependency_result("aggregate_metrics")
        if metrics is None:
            return StepHandlerResult.failure(
                message="Missing aggregate_metrics dependency",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        insights: list[dict[str, Any]] = []
        health_score = 75  # baseline

        sales_summary = metrics.get("sales_summary", {})
        traffic_summary = metrics.get("traffic_summary", {})
        inventory_summary = metrics.get("inventory_summary", {})

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
            health_score += 5

        low_stock = inventory_summary.get("low_stock_alerts", 0)
        if low_stock > 5:
            insights.append(
                {
                    "category": "inventory",
                    "insight": f"{low_stock} SKUs are low or out of stock",
                    "priority": "critical",
                    "action": "Initiate emergency reorder for affected SKUs",
                }
            )
            health_score -= 15
        elif low_stock > 0:
            insights.append(
                {
                    "category": "inventory",
                    "insight": f"{low_stock} SKUs need attention",
                    "priority": "medium",
                    "action": "Review reorder schedules",
                }
            )
            health_score -= 5

        total_records = metrics.get("total_records_processed", 0)
        if total_records > 50:
            health_score += 10
            insights.append(
                {
                    "category": "data_quality",
                    "insight": f"Strong data coverage: {total_records} records analyzed",
                    "priority": "info",
                    "action": "No action needed",
                }
            )

        health_score = max(0, min(100, health_score))

        return StepHandlerResult.success(
            result={
                "insights": insights,
                "insight_count": len(insights),
                "health_score": health_score,
                "health_status": (
                    "excellent" if health_score >= 80
                    else "good" if health_score >= 60
                    else "needs_attention" if health_score >= 40
                    else "critical"
                ),
                "recommendations_count": sum(
                    1 for i in insights if i["priority"] in ("high", "critical")
                ),
                "generated_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"model_version": "insights-v1"},
        )
