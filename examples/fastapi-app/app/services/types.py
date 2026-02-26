"""Shared type definitions for all service modules.

Input types describe what flows into service functions.
Result types describe what each service function returns — the contract
that downstream steps read via dependency injection.

Uses Pydantic BaseModel for both inputs and results so that the functional
handler DSL can inject fully typed models via ``@inputs(Model)`` and
``@depends_on(name=("step", ResultModel))``.

A note on structural vs business validation
--------------------------------------------
This module demonstrates two levels of structural validation:

1. **Schema-derived types** (e.g. ``CustomerSuccessProcessRefundInput``) use
   non-optional Pydantic fields — Pydantic raises ``ValidationError``
   automatically if required fields are missing or the wrong type.

2. **Hand-written input types** (e.g. ``ValidateRefundRequestInput``) use
   ``@model_validator(mode='after')`` with explicit ``check_required_fields``
   because these types accept flexible input shapes (aliased field names,
   multiple optional sources for the same value). The validator runs at
   construction time and raises ``PermanentError`` for missing fields.

For production code, some of these manual validators could be replaced with
Pydantic's declarative ``Field`` constraints (``gt=0``, ``min_length=1``) or
custom field validators (``@field_validator``), keeping the ``@model_validator``
only for cross-field rules like "at least one of customer_id or customer_email
must be present". See https://docs.pydantic.dev/latest/concepts/validators/.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, model_validator

from tasker_core.errors import PermanentError


# ---------------------------------------------------------------------------
# Customer Success input types (schema-derived from input_schema)
# ---------------------------------------------------------------------------


class CustomerSuccessProcessRefundInput(BaseModel):
    """Schema-derived input type for the customer_success_process_refund workflow."""
    ticket_id: str
    customer_id: str
    customer_email: str
    refund_amount: float
    refund_reason: str | None = None
    requires_approval: bool | None = None
    payment_id: str | None = None
    correlation_id: str | None = None
    agent_notes: str | None = None


# ---------------------------------------------------------------------------
# Customer Success input types (hand-written with validation)
# ---------------------------------------------------------------------------


class ValidateRefundRequestInput(BaseModel):
    """Hand-written input with field resolution and validation logic."""
    ticket_id: str | None = None
    order_ref: str | None = None
    customer_id: str | None = None
    refund_amount: float | None = None
    amount: float | None = None
    refund_reason: str | None = None
    reason: str | None = None
    customer_email: str | None = None
    correlation_id: str | None = None

    @property
    def resolved_ticket_id(self) -> str | None:
        return self.ticket_id or self.order_ref

    @property
    def resolved_amount(self) -> float | None:
        return self.refund_amount or self.amount

    @property
    def resolved_reason(self) -> str:
        return self.refund_reason or self.reason or "customer_request"

    @model_validator(mode='after')
    def check_required_fields(self) -> 'ValidateRefundRequestInput':
        """Input validation — required fields are enforced at the model level."""
        missing = []
        if not self.resolved_ticket_id:
            missing.append("ticket_id")
        if not self.customer_id and not self.customer_email:
            missing.append("customer_id")
        if not self.resolved_amount:
            missing.append("refund_amount")
        if missing:
            raise PermanentError(f"Missing required fields: {', '.join(missing)}")
        return self


# ---------------------------------------------------------------------------
# Payments input types (schema-derived from input_schema)
# ---------------------------------------------------------------------------


class PaymentsProcessRefundInput(BaseModel):
    """Schema-derived input type for the payments_process_refund workflow."""
    payment_id: str
    refund_amount: float
    refund_reason: str | None = None
    customer_email: str | None = None
    partial_refund: bool | None = None
    correlation_id: str | None = None


# ---------------------------------------------------------------------------
# Payments input types (hand-written with validation)
# ---------------------------------------------------------------------------


class ValidatePaymentEligibilityInput(BaseModel):
    payment_id: str | None = None
    refund_amount: float | None = None
    amount: float | None = None
    refund_reason: str | None = None
    reason: str | None = None
    partial_refund: bool | None = None
    order_ref: str | None = None
    customer_email: str | None = None

    @property
    def resolved_amount(self) -> float | None:
        return self.refund_amount or self.amount

    @property
    def resolved_reason(self) -> str | None:
        return self.refund_reason or self.reason

    @model_validator(mode='after')
    def check_required_fields(self) -> 'ValidatePaymentEligibilityInput':
        """Input validation — required fields are enforced at the model level."""
        missing = []
        if not self.payment_id and not self.order_ref:
            missing.append("payment_id")
        if not self.resolved_amount:
            missing.append("refund_amount")
        if missing:
            raise PermanentError(f"Missing required fields: {', '.join(missing)}")
        return self


# ---------------------------------------------------------------------------
# Microservices input types (schema-derived from input_schema)
# ---------------------------------------------------------------------------


class MicroservicesUserRegistrationInput(BaseModel):
    """Schema-derived input type for the microservices_user_registration workflow."""
    email: str
    full_name: str
    phone: str | None = None
    plan: str | None = None
    source: str | None = None


# ---------------------------------------------------------------------------
# Microservices input types (hand-written with validation)
# ---------------------------------------------------------------------------


class CreateUserAccountInput(BaseModel):
    email: str | None = None
    username: str | None = None
    full_name: str | None = None
    plan: str | None = None
    referral_code: str | None = None
    preferences: dict[str, Any] | None = None

    @model_validator(mode='after')
    def check_required_fields(self) -> 'CreateUserAccountInput':
        """Input validation — required fields are enforced at the model level."""
        missing = []
        if not self.email:
            missing.append("email")
        if not self.full_name and not self.username:
            missing.append("full_name")
        if missing:
            raise PermanentError(f"Missing required fields: {', '.join(missing)}")
        return self


# ---------------------------------------------------------------------------
# Ecommerce input types (schema-derived from input_schema)
# ---------------------------------------------------------------------------


class EcommerceOrderProcessingInputItems(BaseModel):
    """Schema-derived nested type for cart items."""
    name: str
    quantity: int
    sku: str
    unit_price: float


class EcommerceOrderProcessingInput(BaseModel):
    """Schema-derived input type for the ecommerce_order_processing workflow."""
    customer_email: str
    items: list[EcommerceOrderProcessingInputItems]
    payment_token: str | None = None
    shipping_address: str | None = None


# ---------------------------------------------------------------------------
# Ecommerce input types (hand-written with validation)
# ---------------------------------------------------------------------------


class EcommerceOrderInput(BaseModel):
    items: list[dict[str, Any]] | None = None
    cart_items: list[dict[str, Any]] | None = None
    payment_token: str | None = None
    customer_email: str | None = None
    shipping_address: str | None = None

    @property
    def resolved_items(self) -> list[dict[str, Any]]:
        return self.items or self.cart_items or []


# ---------------------------------------------------------------------------
# Data Pipeline input types (schema-derived from input_schema)
# ---------------------------------------------------------------------------


class DataPipelineAnalyticsPipelineInputDateRange(BaseModel):
    """Schema-derived nested type for date range filter."""
    end_date: str | None = None
    start_date: str | None = None


class DataPipelineAnalyticsPipelineInput(BaseModel):
    """Schema-derived input type for the data_pipeline_analytics_pipeline workflow."""
    date_range: DataPipelineAnalyticsPipelineInputDateRange | None = None
    pipeline_id: str | None = None


# ---------------------------------------------------------------------------
# Data Pipeline input types (hand-written with validation)
# ---------------------------------------------------------------------------


class DataPipelineInput(BaseModel):
    source: str | None = None
    date_range_start: str | None = None
    date_range_end: str | None = None
    granularity: str | None = None


# ---------------------------------------------------------------------------
# Ecommerce inner types
# ---------------------------------------------------------------------------


class EcommerceCartItem(BaseModel):
    """A validated cart/order line item."""
    sku: str
    name: str
    quantity: int
    unit_price: float
    line_total: float


class EcommerceUpdatedProduct(BaseModel):
    """An inventory-updated product record."""
    product_id: str | None = None
    name: str | None = None
    quantity_reserved: int
    reservation_id: str
    warehouse: str
    status: str


# ---------------------------------------------------------------------------
# Ecommerce result types
# ---------------------------------------------------------------------------


class EcommerceValidateCartResult(BaseModel):
    validated_items: list[EcommerceCartItem]
    item_count: int
    subtotal: float
    tax: float
    tax_rate: float
    shipping: float
    total: float
    validated_at: str


class EcommerceProcessPaymentResult(BaseModel):
    payment_id: str
    transaction_id: str
    authorization_code: str
    amount_charged: float
    currency: str
    payment_method_type: str
    gateway_response: str | None = None
    status: str
    processed_at: str


class EcommerceUpdateInventoryResult(BaseModel):
    updated_products: list[EcommerceUpdatedProduct]
    total_items_reserved: int
    inventory_changes: list[dict[str, Any]] | None = None
    inventory_log_id: str
    updated_at: str


class EcommerceCreateOrderResult(BaseModel):
    order_id: str
    order_number: str
    customer_email: str
    items: list[EcommerceCartItem]
    item_count: int
    subtotal: float
    tax: float
    shipping: float
    total: float
    total_amount: float
    payment_id: str
    transaction_id: str
    authorization_code: str
    updated_products: list[EcommerceUpdatedProduct] | None = None
    inventory_log_id: str
    status: str
    created_at: str
    estimated_delivery: str


class EcommerceSendConfirmationResult(BaseModel):
    email_sent: bool
    recipient: str
    email_type: str | None = None
    message_id: str
    subject: str
    body_preview: str | None = None
    channel: str
    template: str
    status: str
    sent_at: str


# ---------------------------------------------------------------------------
# Data Pipeline inner types
# ---------------------------------------------------------------------------


class PipelineDateRange(BaseModel):
    """A start/end date range."""
    start: str
    end: str


class PipelineSalesRecord(BaseModel):
    """A single extracted sales record."""
    record_id: str
    category: str
    region: str
    quantity: int
    unit_price: float
    revenue: float
    timestamp: str


class PipelineTierBreakdown(BaseModel):
    """Category-based breakdown counts (dynamic keys from source data)."""
    model_config = {"extra": "allow"}
    electronics: int | None = None
    clothing: int | None = None
    food: int | None = None
    home: int | None = None
    sports: int | None = None


class PipelineHealthScore(BaseModel):
    """Overall pipeline health score."""
    score: int
    max_score: int
    rating: str
    details: str | None = None


class PipelineInsight(BaseModel):
    """A single generated insight."""
    category: str
    finding: str | None = None
    insight: str | None = None
    metric: float | int | None = None
    recommendation: str | None = None
    action: str | None = None
    priority: str | None = None


# ---------------------------------------------------------------------------
# Data Pipeline result types
# ---------------------------------------------------------------------------


class PipelineExtractSalesResult(BaseModel):
    source: str
    record_count: int
    records: list[PipelineSalesRecord]
    total_amount: float | None = None
    total_revenue: float
    total_quantity: int
    date_range: PipelineDateRange
    extracted_at: str


class PipelineExtractInventoryResult(BaseModel):
    source: str
    record_count: int
    records: list[dict[str, Any]]
    total_quantity: int | None = None
    total_sessions: int | None = None
    total_conversions: int | None = None
    overall_conversion_rate: float | None = None
    warehouses: list[str] | None = None
    products_tracked: int | None = None
    extracted_at: str


class PipelineExtractCustomerResult(BaseModel):
    source: str
    record_count: int
    records: list[dict[str, Any]]
    total_customers: int | None = None
    total_lifetime_value: float | None = None
    avg_lifetime_value: float | None = None
    tier_breakdown: PipelineTierBreakdown | None = None
    total_inventory_value: float | None = None
    low_stock_alerts: int | None = None
    extracted_at: str


class PipelineTransformSalesResult(BaseModel):
    record_count: int
    daily_sales: dict[str, dict[str, Any]] | None = None
    product_sales: dict[str, dict[str, Any]] | None = None
    total_revenue: float
    by_category: dict[str, dict[str, Any]] | None = None
    by_region: dict[str, dict[str, Any]] | None = None
    top_category: str | None = None
    total_categories: int | None = None
    total_regions: int | None = None
    records_processed: int
    transformed_at: str


class PipelineTransformInventoryResult(BaseModel):
    record_count: int
    warehouse_summary: dict[str, dict[str, Any]] | None = None
    product_inventory: dict[str, dict[str, Any]] | None = None
    total_quantity_on_hand: int | None = None
    reorder_alerts: int | None = None
    by_source: dict[str, dict[str, Any]] | None = None
    by_page: dict[str, dict[str, Any]] | None = None
    best_converting_source: str | None = None
    total_sources: int | None = None
    total_pages: int | None = None
    records_processed: int
    transformed_at: str


class PipelineTransformCustomersResult(BaseModel):
    record_count: int
    tier_analysis: dict[str, dict[str, Any]] | None = None
    value_segments: dict[str, dict[str, Any]] | None = None
    total_lifetime_value: float | None = None
    avg_customer_value: float | None = None
    by_warehouse: dict[str, dict[str, Any]] | None = None
    by_category: dict[str, dict[str, Any]] | None = None
    low_stock_items: list[dict[str, Any]] | None = None
    low_stock_count: int | None = None
    total_skus: int | None = None
    records_processed: int
    transformed_at: str


class PipelineAggregateMetricsResult(BaseModel):
    total_revenue: float | None = None
    total_inventory_quantity: int | None = None
    total_customers: int | None = None
    total_customer_lifetime_value: float | None = None
    sales_transactions: int | None = None
    inventory_reorder_alerts: int | None = None
    revenue_per_customer: float | None = None
    inventory_turnover_indicator: float | None = None
    aggregation_complete: bool
    sources_included: int
    sales_summary: dict[str, Any] | None = None
    traffic_summary: dict[str, Any] | None = None
    inventory_summary: dict[str, Any] | None = None
    total_records_processed: int
    data_sources: list[str]
    aggregated_at: str


class PipelineGenerateInsightsResult(BaseModel):
    insights: list[PipelineInsight] | None = None
    health_score: PipelineHealthScore | None = None
    total_metrics_analyzed: int
    pipeline_complete: bool
    insight_count: int
    health_status: str | None = None
    recommendations_count: int
    generated_at: str


# ---------------------------------------------------------------------------
# Microservices inner types
# ---------------------------------------------------------------------------


class MicroservicesMessageSentDetail(BaseModel):
    """A single message-sent record within the welcome sequence."""
    channel: str
    template: str
    status: str


# ---------------------------------------------------------------------------
# Microservices result types
# ---------------------------------------------------------------------------


class MicroservicesCreateUserResult(BaseModel):
    user_id: str
    email: str
    name: str | None = None
    plan: str | None = None
    phone: str | None = None
    source: str | None = None
    status: str
    internal_id: str | None = None
    username: str | None = None
    full_name: str | None = None
    referral_code: str | None = None
    verification_token: str | None = None
    email_verified: bool | None = None
    account_status: str | None = None
    created_at: str


class MicroservicesSetupBillingResult(BaseModel):
    billing_id: str
    user_id: str
    plan: str
    price: float | None = None
    currency: str | None = None
    billing_cycle: str | None = None
    features: list[str] | None = None
    status: str
    billing_required: bool | None = None
    next_billing_date: str | None = None
    subscription_id: str | None = None
    user_internal_id: str | None = None
    pricing: dict[str, Any] | None = None
    limits: dict[str, Any] | None = None
    billing_status: str | None = None
    trial_end: str | None = None
    payment_method_required: bool | None = None
    created_at: str


class MicroservicesInitPreferencesResult(BaseModel):
    preferences_id: str
    user_id: str
    plan: str | None = None
    preferences: dict[str, Any] | None = None
    defaults_applied: int | None = None
    customizations: int | None = None
    status: str
    user_internal_id: str | None = None
    notifications: dict[str, bool] | None = None
    ui_settings: dict[str, Any] | None = None
    feature_flags: dict[str, bool] | None = None
    onboarding_completed: bool | None = None
    created_at: str
    updated_at: str | None = None


class MicroservicesSendWelcomeResult(BaseModel):
    user_id: str
    plan: str | None = None
    channels_used: list[str] | None = None
    messages_sent: int
    welcome_sequence_id: str | None = None
    status: str
    messages_sent_details: list[MicroservicesMessageSentDetail] | None = None
    total_messages: int | None = None
    sequence_id: str
    sent_at: str


class MicroservicesUpdateStatusResult(BaseModel):
    user_id: str
    status: str
    plan: str | None = None
    registration_summary: dict[str, Any] | None = None
    activation_timestamp: str | None = None
    all_services_coordinated: bool | None = None
    services_completed: list[str] | None = None
    internal_id: str | None = None
    email: str | None = None
    account_status: str | None = None
    billing_id: str | None = None
    subscription_id: str | None = None
    onboarding_status: str | None = None
    welcome_messages_sent: int | None = None
    registration_complete: bool
    activated_at: str


# ---------------------------------------------------------------------------
# Customer Success result types
# ---------------------------------------------------------------------------


class CustomerSuccessValidateRefundResult(BaseModel):
    request_validated: bool | None = None
    ticket_id: str
    customer_id: str | None = None
    ticket_status: str | None = None
    customer_tier: str | None = None
    original_purchase_date: str | None = None
    payment_id: str | None = None
    validation_timestamp: str | None = None
    namespace: str | None = None
    request_id: str
    order_ref: str | None = None
    amount: float
    reason: str | None = None
    customer_email: str | None = None
    validation_hash: str | None = None
    eligible: bool
    validated_at: str


class CustomerSuccessCheckPolicyResult(BaseModel):
    policy_checked: bool | None = None
    policy_compliant: bool
    customer_tier: str | None = None
    refund_window_days: int | None = None
    days_since_purchase: int | None = None
    within_refund_window: bool | None = None
    requires_approval: bool
    max_allowed_amount: float | None = None
    policy_checked_at: str | None = None
    namespace: str | None = None
    policy_id: str
    request_id: str
    approval_path: str | None = None
    requires_review: bool | None = None
    amount_tier: str | None = None
    policy_version: str | None = None
    rules_applied: list[str] | None = None
    checked_at: str


class CustomerSuccessApproveRefundResult(BaseModel):
    approval_obtained: bool | None = None
    approval_required: bool | None = None
    auto_approved: bool | None = None
    approval_id: str | None = None
    manager_id: str | None = None
    manager_notes: str | None = None
    approved_at: str
    namespace: str | None = None
    request_id: str
    approved: bool
    approver: str | None = None
    approval_path: str | None = None
    approval_note: str | None = None
    amount_approved: float | None = None


class CustomerSuccessExecuteRefundResult(BaseModel):
    task_delegated: bool | None = None
    target_namespace: str | None = None
    target_workflow: str | None = None
    delegated_task_id: str | None = None
    delegated_task_status: str | None = None
    delegation_timestamp: str | None = None
    correlation_id: str | None = None
    namespace: str | None = None
    refund_id: str
    transaction_ref: str | None = None
    request_id: str
    order_ref: str | None = None
    amount_refunded: float
    currency: str | None = None
    refund_method: str | None = None
    estimated_arrival: str | None = None
    status: str
    executed_at: str


class CustomerSuccessUpdateTicketResult(BaseModel):
    ticket_updated: bool
    ticket_id: str
    previous_status: str | None = None
    new_status: str
    resolution_note: str | None = None
    updated_at: str | None = None
    refund_completed: bool | None = None
    delegated_task_id: str | None = None
    namespace: str | None = None
    request_id: str
    resolution: str | None = None
    customer_notified: bool | None = None
    notification_channel: str | None = None
    refund_id: str | None = None
    amount_refunded: float | None = None
    ticket_status: str | None = None
    resolved_at: str


# ---------------------------------------------------------------------------
# Payments inner types
# ---------------------------------------------------------------------------


class PaymentsLedgerEntry(BaseModel):
    """A single ledger entry in a payment record update."""
    entry_id: str
    type: str
    account: str
    amount: float
    reference: str


# ---------------------------------------------------------------------------
# Payments result types
# ---------------------------------------------------------------------------


class PaymentsValidateEligibilityResult(BaseModel):
    payment_validated: bool | None = None
    payment_id: str
    original_amount: float | None = None
    refund_amount: float
    payment_method: str | None = None
    gateway_provider: str | None = None
    eligibility_status: str | None = None
    validation_timestamp: str | None = None
    namespace: str | None = None
    eligibility_id: str | None = None
    order_ref: str
    amount: float | None = None
    refund_percentage: float | None = None
    reason: str | None = None
    customer_email: str | None = None
    fraud_score: float | None = None
    fraud_flagged: bool | None = None
    within_refund_window: bool | None = None
    eligible: bool
    validated_at: str


class PaymentsProcessGatewayResult(BaseModel):
    refund_processed: bool | None = None
    refund_id: str
    payment_id: str
    refund_amount: float | None = None
    refund_status: str | None = None
    gateway_transaction_id: str | None = None
    gateway_provider: str | None = None
    processed_at: str
    estimated_arrival: str | None = None
    namespace: str | None = None
    gateway_txn_id: str | None = None
    settlement_id: str | None = None
    authorization_code: str | None = None
    order_ref: str | None = None
    amount_processed: float
    currency: str | None = None
    gateway: str | None = None
    gateway_status: str
    processor_response_code: str | None = None
    processor_message: str | None = None
    settlement_batch: str | None = None


class PaymentsUpdateRecordsResult(BaseModel):
    records_updated: bool
    payment_id: str
    refund_id: str | None = None
    record_id: str
    payment_status: str | None = None
    refund_status: str | None = None
    history_entries_created: int | None = None
    updated_at: str | None = None
    namespace: str | None = None
    journal_id: str | None = None
    ledger_entries: list[PaymentsLedgerEntry] | None = None
    order_ref: str | None = None
    amount_recorded: float | None = None
    gateway_txn_id: str | None = None
    reconciliation_status: str | None = None
    fiscal_period: str | None = None
    recorded_at: str


class PaymentsNotifyCustomerResult(BaseModel):
    notification_sent: bool | None = None
    customer_email: str | None = None
    message_id: str
    notification_type: str | None = None
    sent_at: str
    delivery_status: str | None = None
    refund_id: str | None = None
    refund_amount: float | None = None
    namespace: str | None = None
    notification_id: str
    recipient: str | None = None
    channel: str | None = None
    subject: str | None = None
    body_preview: str | None = None
    template: str | None = None
    references: dict[str, Any] | None = None
    status: str
