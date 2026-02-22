"""Shared type definitions for all service modules.

Input types describe what flows into service functions.
Result types describe what each service function returns — the contract
that downstream steps read via dependency injection.

Uses Pydantic BaseModel for both inputs and results so that the functional
handler DSL can inject fully typed models via ``@inputs(Model)`` and
``@depends_on(name=("step", ResultModel))``.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, model_validator

from tasker_core.errors import PermanentError


# ---------------------------------------------------------------------------
# Customer Success input types
# ---------------------------------------------------------------------------


class ValidateRefundRequestInput(BaseModel):
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
# Payments input types
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
# Microservices input types
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
# Ecommerce input types
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
# Data Pipeline input types
# ---------------------------------------------------------------------------


class DataPipelineInput(BaseModel):
    source: str | None = None
    date_range_start: str | None = None
    date_range_end: str | None = None
    granularity: str | None = None


# ---------------------------------------------------------------------------
# Ecommerce result types
# ---------------------------------------------------------------------------


class EcommerceValidateCartResult(BaseModel):
    validated_items: list[dict[str, Any]] | None = None
    item_count: int | None = None
    subtotal: float | None = None
    tax: float | None = None
    tax_rate: float | None = None
    shipping: float | None = None
    total: float | None = None
    validated_at: str | None = None


class EcommerceProcessPaymentResult(BaseModel):
    payment_id: str | None = None
    transaction_id: str | None = None
    authorization_code: str | None = None
    amount_charged: float | None = None
    currency: str | None = None
    payment_method_type: str | None = None
    gateway_response: str | None = None
    status: str | None = None
    processed_at: str | None = None


class EcommerceUpdateInventoryResult(BaseModel):
    updated_products: list[dict[str, Any]] | None = None
    total_items_reserved: int | None = None
    inventory_changes: list[dict[str, Any]] | None = None
    inventory_log_id: str | None = None
    updated_at: str | None = None


class EcommerceCreateOrderResult(BaseModel):
    order_id: str | None = None
    order_number: str | None = None
    customer_email: str | None = None
    items: list[dict[str, Any]] | None = None
    item_count: int | None = None
    subtotal: float | None = None
    tax: float | None = None
    shipping: float | None = None
    total: float | None = None
    total_amount: float | None = None
    payment_id: str | None = None
    transaction_id: str | None = None
    authorization_code: str | None = None
    updated_products: list[dict[str, Any]] | None = None
    inventory_log_id: str | None = None
    status: str | None = None
    created_at: str | None = None
    estimated_delivery: str | None = None


class EcommerceSendConfirmationResult(BaseModel):
    email_sent: bool | None = None
    recipient: str | None = None
    email_type: str | None = None
    message_id: str | None = None
    subject: str | None = None
    body_preview: str | None = None
    channel: str | None = None
    template: str | None = None
    status: str | None = None
    sent_at: str | None = None


# ---------------------------------------------------------------------------
# Data Pipeline result types
# ---------------------------------------------------------------------------


class PipelineExtractSalesResult(BaseModel):
    source: str | None = None
    record_count: int | None = None
    records: list[dict[str, Any]] | None = None
    total_amount: float | None = None
    total_revenue: float | None = None
    total_quantity: int | None = None
    date_range: dict[str, str] | None = None
    extracted_at: str | None = None


class PipelineExtractInventoryResult(BaseModel):
    source: str | None = None
    record_count: int | None = None
    records: list[dict[str, Any]] | None = None
    total_quantity: int | None = None
    total_sessions: int | None = None
    total_conversions: int | None = None
    overall_conversion_rate: float | None = None
    warehouses: list[str] | None = None
    products_tracked: int | None = None
    extracted_at: str | None = None


class PipelineExtractCustomerResult(BaseModel):
    source: str | None = None
    record_count: int | None = None
    records: list[dict[str, Any]] | None = None
    total_customers: int | None = None
    total_lifetime_value: float | None = None
    avg_lifetime_value: float | None = None
    tier_breakdown: dict[str, int] | None = None
    total_inventory_value: float | None = None
    low_stock_alerts: int | None = None
    extracted_at: str | None = None


class PipelineTransformSalesResult(BaseModel):
    record_count: int | None = None
    daily_sales: dict[str, dict[str, Any]] | None = None
    product_sales: dict[str, dict[str, Any]] | None = None
    total_revenue: float | None = None
    by_category: dict[str, dict[str, Any]] | None = None
    by_region: dict[str, dict[str, Any]] | None = None
    top_category: str | None = None
    total_categories: int | None = None
    total_regions: int | None = None
    records_processed: int | None = None
    transformed_at: str | None = None


class PipelineTransformInventoryResult(BaseModel):
    record_count: int | None = None
    warehouse_summary: dict[str, dict[str, Any]] | None = None
    product_inventory: dict[str, dict[str, Any]] | None = None
    total_quantity_on_hand: int | None = None
    reorder_alerts: int | None = None
    by_source: dict[str, dict[str, Any]] | None = None
    by_page: dict[str, dict[str, Any]] | None = None
    best_converting_source: str | None = None
    total_sources: int | None = None
    total_pages: int | None = None
    records_processed: int | None = None
    transformed_at: str | None = None


class PipelineTransformCustomersResult(BaseModel):
    record_count: int | None = None
    tier_analysis: dict[str, dict[str, Any]] | None = None
    value_segments: dict[str, dict[str, Any]] | None = None
    total_lifetime_value: float | None = None
    avg_customer_value: float | None = None
    by_warehouse: dict[str, dict[str, Any]] | None = None
    by_category: dict[str, dict[str, Any]] | None = None
    low_stock_items: list[dict[str, Any]] | None = None
    low_stock_count: int | None = None
    total_skus: int | None = None
    records_processed: int | None = None
    transformed_at: str | None = None


class PipelineAggregateMetricsResult(BaseModel):
    total_revenue: float | None = None
    total_inventory_quantity: int | None = None
    total_customers: int | None = None
    total_customer_lifetime_value: float | None = None
    sales_transactions: int | None = None
    inventory_reorder_alerts: int | None = None
    revenue_per_customer: float | None = None
    inventory_turnover_indicator: float | None = None
    aggregation_complete: bool | None = None
    sources_included: int | None = None
    sales_summary: dict[str, Any] | None = None
    traffic_summary: dict[str, Any] | None = None
    inventory_summary: dict[str, Any] | None = None
    total_records_processed: int | None = None
    data_sources: list[str] | None = None
    aggregated_at: str | None = None


class PipelineGenerateInsightsResult(BaseModel):
    insights: list[dict[str, Any]] | None = None
    health_score: dict[str, Any] | None = None
    total_metrics_analyzed: int | None = None
    pipeline_complete: bool | None = None
    insight_count: int | None = None
    health_status: str | None = None
    recommendations_count: int | None = None
    generated_at: str | None = None


# ---------------------------------------------------------------------------
# Microservices result types
# ---------------------------------------------------------------------------


class MicroservicesCreateUserResult(BaseModel):
    user_id: str | None = None
    email: str | None = None
    name: str | None = None
    plan: str | None = None
    phone: str | None = None
    source: str | None = None
    status: str | None = None
    internal_id: str | None = None
    username: str | None = None
    full_name: str | None = None
    referral_code: str | None = None
    verification_token: str | None = None
    email_verified: bool | None = None
    account_status: str | None = None
    created_at: str | None = None


class MicroservicesSetupBillingResult(BaseModel):
    billing_id: str | None = None
    user_id: str | None = None
    plan: str | None = None
    price: float | None = None
    currency: str | None = None
    billing_cycle: str | None = None
    features: list[str] | None = None
    status: str | None = None
    billing_required: bool | None = None
    next_billing_date: str | None = None
    subscription_id: str | None = None
    user_internal_id: str | None = None
    pricing: dict[str, Any] | None = None
    limits: dict[str, Any] | None = None
    billing_status: str | None = None
    trial_end: str | None = None
    payment_method_required: bool | None = None
    created_at: str | None = None


class MicroservicesInitPreferencesResult(BaseModel):
    preferences_id: str | None = None
    user_id: str | None = None
    plan: str | None = None
    preferences: dict[str, Any] | None = None
    defaults_applied: int | None = None
    customizations: int | None = None
    status: str | None = None
    user_internal_id: str | None = None
    notifications: dict[str, bool] | None = None
    ui_settings: dict[str, Any] | None = None
    feature_flags: dict[str, bool] | None = None
    onboarding_completed: bool | None = None
    created_at: str | None = None
    updated_at: str | None = None


class MicroservicesSendWelcomeResult(BaseModel):
    user_id: str | None = None
    plan: str | None = None
    channels_used: list[str] | None = None
    messages_sent: int | None = None
    welcome_sequence_id: str | None = None
    status: str | None = None
    messages_sent_details: list[dict[str, Any]] | None = None
    total_messages: int | None = None
    sequence_id: str | None = None
    sent_at: str | None = None


class MicroservicesUpdateStatusResult(BaseModel):
    user_id: str | None = None
    status: str | None = None
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
    registration_complete: bool | None = None
    activated_at: str | None = None


# ---------------------------------------------------------------------------
# Customer Success result types
# ---------------------------------------------------------------------------


class CustomerSuccessValidateRefundResult(BaseModel):
    request_validated: bool | None = None
    ticket_id: str | None = None
    customer_id: str | None = None
    ticket_status: str | None = None
    customer_tier: str | None = None
    original_purchase_date: str | None = None
    payment_id: str | None = None
    validation_timestamp: str | None = None
    namespace: str | None = None
    request_id: str | None = None
    order_ref: str | None = None
    amount: float | None = None
    reason: str | None = None
    customer_email: str | None = None
    validation_hash: str | None = None
    eligible: bool | None = None
    validated_at: str | None = None


class CustomerSuccessCheckPolicyResult(BaseModel):
    policy_checked: bool | None = None
    policy_compliant: bool | None = None
    customer_tier: str | None = None
    refund_window_days: int | None = None
    days_since_purchase: int | None = None
    within_refund_window: bool | None = None
    requires_approval: bool | None = None
    max_allowed_amount: float | None = None
    policy_checked_at: str | None = None
    namespace: str | None = None
    policy_id: str | None = None
    request_id: str | None = None
    approval_path: str | None = None
    requires_review: bool | None = None
    amount_tier: str | None = None
    policy_version: str | None = None
    rules_applied: list[str] | None = None
    checked_at: str | None = None


class CustomerSuccessApproveRefundResult(BaseModel):
    approval_obtained: bool | None = None
    approval_required: bool | None = None
    auto_approved: bool | None = None
    approval_id: str | None = None
    manager_id: str | None = None
    manager_notes: str | None = None
    approved_at: str | None = None
    namespace: str | None = None
    request_id: str | None = None
    approved: bool | None = None
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
    refund_id: str | None = None
    transaction_ref: str | None = None
    request_id: str | None = None
    order_ref: str | None = None
    amount_refunded: float | None = None
    currency: str | None = None
    refund_method: str | None = None
    estimated_arrival: str | None = None
    status: str | None = None
    executed_at: str | None = None


class CustomerSuccessUpdateTicketResult(BaseModel):
    ticket_updated: bool | None = None
    ticket_id: str | None = None
    previous_status: str | None = None
    new_status: str | None = None
    resolution_note: str | None = None
    updated_at: str | None = None
    refund_completed: bool | None = None
    delegated_task_id: str | None = None
    namespace: str | None = None
    request_id: str | None = None
    resolution: str | None = None
    customer_notified: bool | None = None
    notification_channel: str | None = None
    refund_id: str | None = None
    amount_refunded: float | None = None
    ticket_status: str | None = None
    resolved_at: str | None = None


# ---------------------------------------------------------------------------
# Payments result types
# ---------------------------------------------------------------------------


class PaymentsValidateEligibilityResult(BaseModel):
    payment_validated: bool | None = None
    payment_id: str | None = None
    original_amount: float | None = None
    refund_amount: float | None = None
    payment_method: str | None = None
    gateway_provider: str | None = None
    eligibility_status: str | None = None
    validation_timestamp: str | None = None
    namespace: str | None = None
    eligibility_id: str | None = None
    order_ref: str | None = None
    amount: float | None = None
    refund_percentage: float | None = None
    reason: str | None = None
    customer_email: str | None = None
    fraud_score: float | None = None
    fraud_flagged: bool | None = None
    within_refund_window: bool | None = None
    eligible: bool | None = None
    validated_at: str | None = None


class PaymentsProcessGatewayResult(BaseModel):
    refund_processed: bool | None = None
    refund_id: str | None = None
    payment_id: str | None = None
    refund_amount: float | None = None
    refund_status: str | None = None
    gateway_transaction_id: str | None = None
    gateway_provider: str | None = None
    processed_at: str | None = None
    estimated_arrival: str | None = None
    namespace: str | None = None
    gateway_txn_id: str | None = None
    settlement_id: str | None = None
    authorization_code: str | None = None
    order_ref: str | None = None
    amount_processed: float | None = None
    currency: str | None = None
    gateway: str | None = None
    gateway_status: str | None = None
    processor_response_code: str | None = None
    processor_message: str | None = None
    settlement_batch: str | None = None


class PaymentsUpdateRecordsResult(BaseModel):
    records_updated: bool | None = None
    payment_id: str | None = None
    refund_id: str | None = None
    record_id: str | None = None
    payment_status: str | None = None
    refund_status: str | None = None
    history_entries_created: int | None = None
    updated_at: str | None = None
    namespace: str | None = None
    journal_id: str | None = None
    ledger_entries: list[dict[str, Any]] | None = None
    order_ref: str | None = None
    amount_recorded: float | None = None
    gateway_txn_id: str | None = None
    reconciliation_status: str | None = None
    fiscal_period: str | None = None
    recorded_at: str | None = None


class PaymentsNotifyCustomerResult(BaseModel):
    notification_sent: bool | None = None
    customer_email: str | None = None
    message_id: str | None = None
    notification_type: str | None = None
    sent_at: str | None = None
    delivery_status: str | None = None
    refund_id: str | None = None
    refund_amount: float | None = None
    namespace: str | None = None
    notification_id: str | None = None
    recipient: str | None = None
    channel: str | None = None
    subject: str | None = None
    body_preview: str | None = None
    template: str | None = None
    references: dict[str, Any] | None = None
    status: str | None = None
