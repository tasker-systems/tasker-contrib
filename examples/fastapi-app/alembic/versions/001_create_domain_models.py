"""Create domain models for the FastAPI example app.

Revision ID: 001
Create Date: 2026-02-12

"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB, UUID

revision = "001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "orders",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("customer_email", sa.String(255), nullable=False),
        sa.Column("items", JSONB, nullable=False, server_default="[]"),
        sa.Column("total", sa.Numeric(10, 2), nullable=True),
        sa.Column(
            "status",
            sa.String(50),
            nullable=False,
            server_default="pending",
        ),
        sa.Column("task_uuid", UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_orders_task_uuid", "orders", ["task_uuid"])
    op.create_index("ix_orders_status", "orders", ["status"])

    op.create_table(
        "analytics_jobs",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("source", sa.String(100), nullable=False),
        sa.Column("dataset_url", sa.String(500), nullable=True),
        sa.Column(
            "status",
            sa.String(50),
            nullable=False,
            server_default="pending",
        ),
        sa.Column("task_uuid", UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_analytics_jobs_task_uuid", "analytics_jobs", ["task_uuid"])
    op.create_index("ix_analytics_jobs_status", "analytics_jobs", ["status"])

    op.create_table(
        "service_requests",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.String(100), nullable=False),
        sa.Column("request_type", sa.String(100), nullable=False),
        sa.Column(
            "status",
            sa.String(50),
            nullable=False,
            server_default="pending",
        ),
        sa.Column("result", JSONB, nullable=True),
        sa.Column("task_uuid", UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index("ix_service_requests_task_uuid", "service_requests", ["task_uuid"])
    op.create_index("ix_service_requests_status", "service_requests", ["status"])

    op.create_table(
        "compliance_checks",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("order_ref", sa.String(100), nullable=False),
        sa.Column("namespace", sa.String(100), nullable=False),
        sa.Column(
            "status",
            sa.String(50),
            nullable=False,
            server_default="pending",
        ),
        sa.Column("task_uuid", UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_compliance_checks_task_uuid", "compliance_checks", ["task_uuid"]
    )
    op.create_index("ix_compliance_checks_status", "compliance_checks", ["status"])


def downgrade() -> None:
    op.drop_table("compliance_checks")
    op.drop_table("service_requests")
    op.drop_table("analytics_jobs")
    op.drop_table("orders")
