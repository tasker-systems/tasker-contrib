/**
 * Zod schemas and types for all service modules.
 *
 * Single source of truth: each schema defines both runtime validation and
 * the corresponding TypeScript type via z.infer<>. Handlers use schemas
 * for input validation (.parse() / .safeParse()), services use the inferred
 * types as lightweight contracts.
 *
 * Naming convention: TypeName + "Schema" for the validator object,
 * plain TypeName for the inferred type.
 *   EcommerceValidateCartResultSchema → z.object({...}).passthrough()
 *   EcommerceValidateCartResult       → z.infer<typeof ...>
 */

import { z } from "zod";

// ---------------------------------------------------------------------------
// Ecommerce input types
// ---------------------------------------------------------------------------

export const EcommerceOrderProcessingInputCartItemsSchema = z.object({
  name: z.string(),
  price: z.number(),
  quantity: z.number(),
  sku: z.string(),
});
export type EcommerceOrderProcessingInputCartItems = z.infer<
  typeof EcommerceOrderProcessingInputCartItemsSchema
>;

export const EcommerceOrderProcessingInputPaymentInfoSchema = z.object({
  card_last_four: z.string().optional(),
  method: z.string().optional(),
});
export type EcommerceOrderProcessingInputPaymentInfo = z.infer<
  typeof EcommerceOrderProcessingInputPaymentInfoSchema
>;

export const EcommerceOrderProcessingInputSchema = z.object({
  cart_items: z.array(EcommerceOrderProcessingInputCartItemsSchema),
  customer_email: z.string(),
  payment_info: EcommerceOrderProcessingInputPaymentInfoSchema.optional(),
});
export type EcommerceOrderProcessingInput = z.infer<
  typeof EcommerceOrderProcessingInputSchema
>;

export const CartItemSchema = z.object({
  sku: z.string(),
  name: z.string(),
  price: z.number(),
  quantity: z.number(),
});
export type CartItem = z.infer<typeof CartItemSchema>;

export const PaymentInfoSchema = z.object({
  method: z.string(),
  card_last_four: z.string().optional(),
  token: z.string(),
  amount: z.number(),
});
export type PaymentInfo = z.infer<typeof PaymentInfoSchema>;

// ---------------------------------------------------------------------------
// Ecommerce result types
// ---------------------------------------------------------------------------

export const EcommerceValidateCartResultSchema = z
  .object({
    validated_items: z.array(CartItemSchema),
    item_count: z.number(),
    subtotal: z.number(),
    tax: z.number(),
    tax_rate: z.number(),
    shipping: z.number(),
    total: z.number(),
    free_shipping: z.boolean(),
    validation_warnings: z.array(z.string()),
  })
  .passthrough();
export type EcommerceValidateCartResult = z.infer<
  typeof EcommerceValidateCartResultSchema
>;

export const EcommerceProcessPaymentResultSchema = z
  .object({
    payment_id: z.string(),
    transaction_id: z.string(),
    status: z.literal("succeeded"),
    amount_charged: z.number(),
    currency: z.literal("USD"),
    payment_method: z.string(),
    auth_code: z.string(),
    processing_fee: z.number(),
    net_amount: z.number(),
    card_last_four: z.string(),
    gateway: z.string(),
    authorized_at: z.string(),
  })
  .passthrough();
export type EcommerceProcessPaymentResult = z.infer<
  typeof EcommerceProcessPaymentResultSchema
>;

export const InventoryProductSchema = z.object({
  sku: z.string(),
  name: z.string(),
  previous_stock: z.number(),
  new_stock: z.number(),
  quantity_reserved: z.number(),
  reservation_id: z.string(),
  warehouse: z.string(),
});
export type InventoryProduct = z.infer<typeof InventoryProductSchema>;

export const EcommerceUpdateInventoryResultSchema = z
  .object({
    updated_products: z.array(InventoryProductSchema),
    total_items_reserved: z.number(),
    inventory_log_id: z.string(),
    updated_at: z.string(),
    reservation_expires_at: z.string(),
    all_items_available: z.boolean(),
  })
  .passthrough();
export type EcommerceUpdateInventoryResult = z.infer<
  typeof EcommerceUpdateInventoryResultSchema
>;

export const OrderItemSchema = z.object({
  sku: z.string(),
  name: z.string(),
  quantity: z.number(),
  unit_price: z.number(),
  line_total: z.number(),
});
export type OrderItem = z.infer<typeof OrderItemSchema>;

export const EcommerceCreateOrderResultSchema = z
  .object({
    order_id: z.number(),
    order_number: z.string(),
    status: z.literal("confirmed"),
    total_amount: z.number(),
    customer_email: z.string(),
    created_at: z.string(),
    estimated_delivery: z.string(),
    items: z.array(OrderItemSchema),
    subtotal: z.number(),
    tax: z.number(),
    shipping: z.number(),
    transaction_id: z.string(),
    inventory_reservations: z.number(),
  })
  .passthrough();
export type EcommerceCreateOrderResult = z.infer<
  typeof EcommerceCreateOrderResultSchema
>;

export const EcommerceSendConfirmationResultSchema = z
  .object({
    email_id: z.string(),
    recipient: z.string(),
    subject: z.string(),
    status: z.literal("sent"),
    sent_at: z.string(),
    template: z.string(),
    template_data: z.object({
      customer_name: z.string(),
      order_number: z.string(),
      total_amount: z.number(),
      estimated_delivery: z.string(),
      items: z.array(OrderItemSchema),
    }),
    provider: z.string(),
  })
  .passthrough();
export type EcommerceSendConfirmationResult = z.infer<
  typeof EcommerceSendConfirmationResultSchema
>;

// ---------------------------------------------------------------------------
// Data Pipeline input types
// ---------------------------------------------------------------------------

export const AnalyticsPipelineInputDateRangeSchema = z.object({
  end_date: z.string().optional(),
  start_date: z.string().optional(),
});
export type AnalyticsPipelineInputDateRange = z.infer<
  typeof AnalyticsPipelineInputDateRangeSchema
>;

export const AnalyticsPipelineInputSchema = z.object({
  date_range: AnalyticsPipelineInputDateRangeSchema.optional(),
  pipeline_id: z.string().optional(),
});
export type AnalyticsPipelineInput = z.infer<
  typeof AnalyticsPipelineInputSchema
>;

export const DataRecordSchema = z.object({
  id: z.string(),
  value: z.number(),
  category: z.string(),
  timestamp: z.string(),
});
export type DataRecord = z.infer<typeof DataRecordSchema>;

export const DateRangeSchema = z.object({
  start: z.string(),
  end: z.string(),
});
export type DateRange = z.infer<typeof DateRangeSchema>;

export const WarehouseRecordSchema = z.object({
  warehouse_id: z.string(),
  total_skus: z.number(),
  total_units: z.number(),
  low_stock_skus: z.number(),
  out_of_stock_skus: z.number(),
});
export type WarehouseRecord = z.infer<typeof WarehouseRecordSchema>;

export const CustomerRecordSchema = z.object({
  customer_id: z.string(),
  name: z.string(),
  tier: z.string(),
  lifetime_value: z.number(),
  join_date: z.string(),
});
export type CustomerRecord = z.infer<typeof CustomerRecordSchema>;

// ---------------------------------------------------------------------------
// Data Pipeline result types
// ---------------------------------------------------------------------------

export const PipelineExtractSalesResultSchema = z
  .object({
    records: z.array(DataRecordSchema),
    extracted_at: z.string(),
    source: z.string(),
    total_amount: z.number(),
    date_range: DateRangeSchema,
    record_count: z.number(),
    extraction_sources: z.number(),
    schema_version: z.string(),
  })
  .passthrough();
export type PipelineExtractSalesResult = z.infer<
  typeof PipelineExtractSalesResultSchema
>;

export const PipelineExtractInventoryResultSchema = z
  .object({
    records: z.array(WarehouseRecordSchema),
    extracted_at: z.string(),
    source: z.string(),
    total_quantity: z.number(),
    warehouses: z.array(z.string()),
    products_tracked: z.number(),
    record_count: z.number(),
    warehouse_count: z.number(),
    include_archived: z.unknown(),
  })
  .passthrough();
export type PipelineExtractInventoryResult = z.infer<
  typeof PipelineExtractInventoryResultSchema
>;

export const PipelineExtractCustomerResultSchema = z
  .object({
    records: z.array(CustomerRecordSchema),
    extracted_at: z.string(),
    source: z.string(),
    total_customers: z.number(),
    total_lifetime_value: z.number(),
    tier_breakdown: z.record(z.string(), z.number()),
    avg_lifetime_value: z.number(),
    active_customers: z.number(),
    new_customers_in_period: z.number(),
    churn_count: z.number(),
    region_breakdown: z.record(z.string(), z.number()),
    date_range: DateRangeSchema,
  })
  .passthrough();
export type PipelineExtractCustomerResult = z.infer<
  typeof PipelineExtractCustomerResultSchema
>;

export const DailySalesEntrySchema = z.object({
  total_amount: z.number(),
  order_count: z.number(),
  avg_order_value: z.number(),
});
export type DailySalesEntry = z.infer<typeof DailySalesEntrySchema>;

export const ProductSalesEntrySchema = z.object({
  total_quantity: z.number(),
  total_revenue: z.number(),
  order_count: z.number(),
});
export type ProductSalesEntry = z.infer<typeof ProductSalesEntrySchema>;

export const PipelineTransformSalesResultSchema = z
  .object({
    record_count: z.number(),
    daily_sales: z.record(z.string(), DailySalesEntrySchema),
    product_sales: z.record(z.string(), ProductSalesEntrySchema),
    total_revenue: z.number(),
    transformation_type: z.string(),
    source: z.string(),
    unique_categories: z.number(),
    avg_transaction_value: z.number(),
    transformed_at: z.string(),
  })
  .passthrough();
export type PipelineTransformSalesResult = z.infer<
  typeof PipelineTransformSalesResultSchema
>;

export const WarehouseSummaryEntrySchema = z.object({
  total_quantity: z.number(),
  product_count: z.number(),
  reorder_alerts: z.number(),
});
export type WarehouseSummaryEntry = z.infer<typeof WarehouseSummaryEntrySchema>;

export const ProductInventoryEntrySchema = z.object({
  total_quantity: z.number(),
  warehouse_count: z.number(),
  needs_reorder: z.boolean(),
});
export type ProductInventoryEntry = z.infer<typeof ProductInventoryEntrySchema>;

export const PipelineTransformInventoryResultSchema = z
  .object({
    record_count: z.number(),
    warehouse_summary: z.record(z.string(), WarehouseSummaryEntrySchema),
    product_inventory: z.record(z.string(), ProductInventoryEntrySchema),
    total_quantity_on_hand: z.number(),
    reorder_alerts: z.number(),
    transformation_type: z.string(),
    source: z.string(),
    transformed_at: z.string(),
  })
  .passthrough();
export type PipelineTransformInventoryResult = z.infer<
  typeof PipelineTransformInventoryResultSchema
>;

export const TierAnalysisEntrySchema = z.object({
  customer_count: z.number(),
  total_lifetime_value: z.number(),
  avg_lifetime_value: z.number(),
});
export type TierAnalysisEntry = z.infer<typeof TierAnalysisEntrySchema>;

export const PipelineTransformCustomersResultSchema = z
  .object({
    record_count: z.number(),
    tier_analysis: z.record(z.string(), TierAnalysisEntrySchema),
    value_segments: z.object({
      high_value: z.number(),
      medium_value: z.number(),
      low_value: z.number(),
    }),
    total_lifetime_value: z.number(),
    avg_customer_value: z.number(),
    transformation_type: z.string(),
    source: z.string(),
    region_distribution: z.unknown(),
    transformed_at: z.string(),
  })
  .passthrough();
export type PipelineTransformCustomersResult = z.infer<
  typeof PipelineTransformCustomersResultSchema
>;

export const PipelineAggregateMetricsResultSchema = z
  .object({
    total_revenue: z.number(),
    total_inventory_quantity: z.number(),
    total_customers: z.number(),
    total_customer_lifetime_value: z.number(),
    sales_transactions: z.number(),
    inventory_reorder_alerts: z.number(),
    revenue_per_customer: z.number(),
    inventory_turnover_indicator: z.number(),
    aggregation_complete: z.boolean(),
    sources_included: z.number(),
    aggregated_at: z.string(),
  })
  .passthrough();
export type PipelineAggregateMetricsResult = z.infer<
  typeof PipelineAggregateMetricsResultSchema
>;

export const InsightEntrySchema = z.object({
  category: z.string(),
  finding: z.string(),
  metric: z.number(),
  recommendation: z.string(),
});
export type InsightEntry = z.infer<typeof InsightEntrySchema>;

export const PipelineGenerateInsightsResultSchema = z
  .object({
    insights: z.array(InsightEntrySchema),
    health_score: z.object({
      score: z.number(),
      max_score: z.number(),
      rating: z.string(),
      details: z.string().optional(),
    }),
    total_metrics_analyzed: z.number(),
    pipeline_complete: z.boolean(),
    generated_at: z.string(),
  })
  .passthrough();
export type PipelineGenerateInsightsResult = z.infer<
  typeof PipelineGenerateInsightsResultSchema
>;

// ---------------------------------------------------------------------------
// Customer Success input types
// ---------------------------------------------------------------------------

export const CustomerSuccessProcessRefundInputSchema = z.object({
  agent_notes: z.string().optional(),
  correlation_id: z.string().optional(),
  customer_email: z.string(),
  customer_id: z.string(),
  payment_id: z.string().optional(),
  refund_amount: z.number(),
  refund_reason: z.string().optional(),
  requires_approval: z.boolean().optional(),
  ticket_id: z.string(),
});
export type CustomerSuccessProcessRefundInput = z.infer<
  typeof CustomerSuccessProcessRefundInputSchema
>;

export const ValidateRefundRequestInputSchema = z.object({
  ticketId: z.string(),
  customerId: z.string(),
  refundAmount: z.number(),
  refundReason: z.string(),
});
export type ValidateRefundRequestInput = z.infer<
  typeof ValidateRefundRequestInputSchema
>;

// ---------------------------------------------------------------------------
// Customer Success result types
// ---------------------------------------------------------------------------

export const CustomerSuccessValidateRefundResultSchema = z
  .object({
    request_validated: z.literal(true),
    ticket_id: z.string().optional(),
    customer_id: z.string().optional(),
    ticket_status: z.string(),
    customer_tier: z.string(),
    original_purchase_date: z.string(),
    payment_id: z.string(),
    validation_timestamp: z.string(),
    namespace: z.string(),
  })
  .passthrough();
export type CustomerSuccessValidateRefundResult = z.infer<
  typeof CustomerSuccessValidateRefundResultSchema
>;

export const CustomerSuccessCheckRefundPolicyResultSchema = z
  .object({
    policy_checked: z.literal(true),
    policy_compliant: z.boolean(),
    customer_tier: z.string(),
    refund_window_days: z.number(),
    days_since_purchase: z.number(),
    within_refund_window: z.boolean(),
    requires_approval: z.boolean(),
    approval_path: z
      .union([
        z.literal("auto"),
        z.literal("manager"),
        z.literal("director"),
      ])
      .optional(),
    max_allowed_amount: z.number(),
    policy_checked_at: z.string(),
    namespace: z.string(),
  })
  .passthrough();
export type CustomerSuccessCheckRefundPolicyResult = z.infer<
  typeof CustomerSuccessCheckRefundPolicyResultSchema
>;

export const CustomerSuccessApproveRefundResultSchema = z
  .object({
    approval_obtained: z.literal(true),
    approval_required: z.boolean(),
    auto_approved: z.boolean(),
    approval_id: z.union([z.string(), z.null()]),
    manager_id: z.union([z.string(), z.null()]),
    manager_notes: z.string(),
    approved_at: z.string(),
    namespace: z.string(),
  })
  .passthrough();
export type CustomerSuccessApproveRefundResult = z.infer<
  typeof CustomerSuccessApproveRefundResultSchema
>;

export const CustomerSuccessExecuteRefundResultSchema = z
  .object({
    task_delegated: z.literal(true),
    target_namespace: z.string(),
    target_workflow: z.string(),
    delegated_task_id: z.string(),
    delegated_task_status: z.string(),
    delegation_timestamp: z.string(),
    correlation_id: z.string(),
    namespace: z.string(),
  })
  .passthrough();
export type CustomerSuccessExecuteRefundResult = z.infer<
  typeof CustomerSuccessExecuteRefundResultSchema
>;

export const CustomerSuccessUpdateTicketResultSchema = z
  .object({
    ticket_updated: z.literal(true),
    ticket_id: z.string(),
    previous_status: z.string(),
    new_status: z.string(),
    resolution_note: z.string(),
    updated_at: z.string(),
    refund_completed: z.boolean(),
    delegated_task_id: z.string(),
    namespace: z.string(),
  })
  .passthrough();
export type CustomerSuccessUpdateTicketResult = z.infer<
  typeof CustomerSuccessUpdateTicketResultSchema
>;

// ---------------------------------------------------------------------------
// Payments input types
// ---------------------------------------------------------------------------

export const PaymentsProcessRefundInputSchema = z.object({
  correlation_id: z.string().optional(),
  customer_email: z.string().optional(),
  partial_refund: z.boolean().optional(),
  payment_id: z.string(),
  refund_amount: z.number(),
  refund_reason: z
    .union([
      z.literal("customer_request"),
      z.literal("fraud"),
      z.literal("system_error"),
      z.literal("chargeback"),
    ])
    .optional(),
});
export type PaymentsProcessRefundInput = z.infer<
  typeof PaymentsProcessRefundInputSchema
>;

export const ValidatePaymentEligibilityInputSchema = z.object({
  paymentId: z.string(),
  refundAmount: z.number(),
});
export type ValidatePaymentEligibilityInput = z.infer<
  typeof ValidatePaymentEligibilityInputSchema
>;

// ---------------------------------------------------------------------------
// Payments result types
// ---------------------------------------------------------------------------

export const PaymentsValidateEligibilityResultSchema = z
  .object({
    payment_validated: z.literal(true),
    payment_id: z.string(),
    original_amount: z.number(),
    refund_amount: z.number(),
    payment_method: z.string(),
    gateway_provider: z.string(),
    eligibility_status: z.string(),
    validation_timestamp: z.string(),
    namespace: z.string(),
  })
  .passthrough();
export type PaymentsValidateEligibilityResult = z.infer<
  typeof PaymentsValidateEligibilityResultSchema
>;

export const PaymentsProcessGatewayResultSchema = z
  .object({
    refund_processed: z.literal(true),
    refund_id: z.string(),
    payment_id: z.string(),
    refund_amount: z.number(),
    refund_status: z.string(),
    gateway_transaction_id: z.string(),
    gateway_provider: z.string(),
    processed_at: z.string(),
    estimated_arrival: z.string(),
    namespace: z.string(),
  })
  .passthrough();
export type PaymentsProcessGatewayResult = z.infer<
  typeof PaymentsProcessGatewayResultSchema
>;

export const PaymentsUpdateRecordsResultSchema = z
  .object({
    records_updated: z.literal(true),
    payment_id: z.string(),
    refund_id: z.string(),
    record_id: z.string(),
    payment_status: z.string(),
    refund_status: z.string(),
    history_entries_created: z.number(),
    updated_at: z.string(),
    namespace: z.string(),
  })
  .passthrough();
export type PaymentsUpdateRecordsResult = z.infer<
  typeof PaymentsUpdateRecordsResultSchema
>;

export const PaymentsNotifyCustomerResultSchema = z
  .object({
    notification_sent: z.literal(true),
    customer_email: z.string(),
    message_id: z.string(),
    notification_type: z.string(),
    sent_at: z.string(),
    delivery_status: z.string(),
    refund_id: z.string(),
    refund_amount: z.number(),
    namespace: z.string(),
  })
  .passthrough();
export type PaymentsNotifyCustomerResult = z.infer<
  typeof PaymentsNotifyCustomerResultSchema
>;

// ---------------------------------------------------------------------------
// Microservices input types
// ---------------------------------------------------------------------------

export const UserRegistrationInputSchema = z.object({
  email: z.string(),
  metadata: z.unknown().optional(),
  plan: z
    .union([
      z.literal("free"),
      z.literal("pro"),
      z.literal("enterprise"),
      z.literal("basic"),
      z.literal("standard"),
      z.literal("premium"),
    ])
    .optional(),
  username: z.string(),
});
export type UserRegistrationInput = z.infer<typeof UserRegistrationInputSchema>;

export const CreateUserAccountInputSchema = z.object({
  email: z.string(),
  username: z.string(),
  plan: z.string().optional(),
  metadata: z.record(z.string(), z.unknown()).optional(),
});
export type CreateUserAccountInput = z.infer<
  typeof CreateUserAccountInputSchema
>;

export const BillingTierSchema = z.object({
  price: z.number(),
  features: z.array(z.string()),
  billing_required: z.boolean(),
});
export type BillingTier = z.infer<typeof BillingTierSchema>;

// ---------------------------------------------------------------------------
// Microservices result types
// ---------------------------------------------------------------------------

export const MicroservicesCreateUserResultSchema = z
  .object({
    user_id: z.string(),
    email: z.string(),
    name: z.string(),
    plan: z.string(),
    phone: z.null(),
    source: z.string(),
    status: z.string(),
    created_at: z.string(),
    api_key: z.string(),
    auth_provider: z.string(),
  })
  .passthrough();
export type MicroservicesCreateUserResult = z.infer<
  typeof MicroservicesCreateUserResultSchema
>;

export const MicroservicesSetupBillingActiveResultSchema = z
  .object({
    billing_id: z.string(),
    user_id: z.string(),
    plan: z.union([
      z.literal("free"),
      z.literal("pro"),
      z.literal("enterprise"),
    ]),
    price: z.number(),
    currency: z.string(),
    billing_cycle: z.string(),
    features: z.array(z.string()),
    status: z.string(),
    next_billing_date: z.string(),
    created_at: z.string(),
  })
  .passthrough();
export type MicroservicesSetupBillingActiveResult = z.infer<
  typeof MicroservicesSetupBillingActiveResultSchema
>;

export const MicroservicesSetupBillingSkippedResultSchema = z
  .object({
    user_id: z.string(),
    plan: z.union([
      z.literal("free"),
      z.literal("pro"),
      z.literal("enterprise"),
    ]),
    billing_required: z.literal(false),
    status: z.string(),
    message: z.string(),
  })
  .passthrough();
export type MicroservicesSetupBillingSkippedResult = z.infer<
  typeof MicroservicesSetupBillingSkippedResultSchema
>;

export const MicroservicesSetupBillingResultSchema = z.union([
  MicroservicesSetupBillingActiveResultSchema,
  MicroservicesSetupBillingSkippedResultSchema,
]);
export type MicroservicesSetupBillingResult = z.infer<
  typeof MicroservicesSetupBillingResultSchema
>;

export const MicroservicesInitPreferencesResultSchema = z
  .object({
    preferences_id: z.string(),
    user_id: z.string(),
    plan: z.string(),
    preferences: z.record(z.string(), z.unknown()),
    defaults_applied: z.number(),
    customizations: z.number(),
    status: z.string(),
    created_at: z.string(),
    updated_at: z.string(),
  })
  .passthrough();
export type MicroservicesInitPreferencesResult = z.infer<
  typeof MicroservicesInitPreferencesResultSchema
>;

export const MicroservicesSendWelcomeResultSchema = z
  .object({
    user_id: z.string(),
    plan: z.string(),
    channels_used: z.array(z.string()),
    messages_sent: z.number(),
    welcome_sequence_id: z.string(),
    status: z.string(),
    sent_at: z.string(),
    recipient: z.string(),
  })
  .passthrough();
export type MicroservicesSendWelcomeResult = z.infer<
  typeof MicroservicesSendWelcomeResultSchema
>;

export const MicroservicesUpdateStatusResultSchema = z
  .object({
    user_id: z.string(),
    status: z.string(),
    plan: z.string(),
    registration_summary: z.record(z.string(), z.unknown()),
    activation_timestamp: z.string(),
    all_services_coordinated: z.boolean(),
    services_completed: z.array(z.string()),
  })
  .passthrough();
export type MicroservicesUpdateStatusResult = z.infer<
  typeof MicroservicesUpdateStatusResultSchema
>;
