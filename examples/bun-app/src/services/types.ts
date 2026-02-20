/**
 * Shared type definitions for all service modules.
 *
 * Input types describe what flows into service functions.
 * Result types describe what each service function returns — the contract
 * that downstream steps read via dependency injection.
 */

// ---------------------------------------------------------------------------
// Ecommerce input types
// ---------------------------------------------------------------------------

export interface CartItem {
  sku: string;
  name: string;
  price: number;
  quantity: number;
}

export interface PaymentInfo {
  method: string;
  card_last_four?: string;
  token: string;
  amount: number;
}

// ---------------------------------------------------------------------------
// Ecommerce result types
// ---------------------------------------------------------------------------

export interface EcommerceValidateCartResult {
  [key: string]: unknown;
  validated_items: CartItem[];
  item_count: number;
  subtotal: number;
  tax: number;
  tax_rate: number;
  shipping: number;
  total: number;
  free_shipping: boolean;
  validation_warnings: string[];
}

export interface EcommerceProcessPaymentResult {
  [key: string]: unknown;
  payment_id: string;
  transaction_id: string;
  status: string;
  amount_charged: number;
  currency: string;
  payment_method: string;
  auth_code: string;
  processing_fee: number;
  net_amount: number;
  card_last_four: string;
  gateway: string;
  authorized_at: string;
}

export interface InventoryProduct {
  sku: string;
  name: string;
  previous_stock: number;
  new_stock: number;
  quantity_reserved: number;
  reservation_id: string;
  warehouse: string;
}

export interface EcommerceUpdateInventoryResult {
  [key: string]: unknown;
  updated_products: InventoryProduct[];
  total_items_reserved: number;
  inventory_log_id: string;
  updated_at: string;
  reservation_expires_at: string;
  all_items_available: boolean;
}

export interface EcommerceCreateOrderResult {
  [key: string]: unknown;
  order_id: number;
  order_number: string;
  status: string;
  total_amount: unknown;
  customer_email: string;
  created_at: string;
  estimated_delivery: string;
  items: unknown;
  subtotal: unknown;
  tax: unknown;
  shipping: unknown;
  transaction_id: unknown;
  inventory_reservations: number;
}

export interface EcommerceSendConfirmationResult {
  [key: string]: unknown;
  email_id: string;
  recipient: string;
  subject: string;
  status: string;
  sent_at: string;
  template: string;
  template_data: {
    customer_name: string;
    order_number: string;
    total_amount: number;
    estimated_delivery: string;
    items: unknown;
  };
  provider: string;
}

// ---------------------------------------------------------------------------
// Data Pipeline input types
// ---------------------------------------------------------------------------

export interface DataRecord {
  id: string;
  value: number;
  category: string;
  timestamp: string;
}

export interface DateRange {
  start: string;
  end: string;
}

export interface WarehouseRecord {
  warehouse_id: string;
  total_skus: number;
  total_units: number;
  low_stock_skus: number;
  out_of_stock_skus: number;
}

export interface CustomerRecord {
  customer_id: string;
  name: string;
  tier: string;
  lifetime_value: number;
  join_date: string;
}

// ---------------------------------------------------------------------------
// Data Pipeline result types
// ---------------------------------------------------------------------------

export interface PipelineExtractSalesResult {
  [key: string]: unknown;
  records: DataRecord[];
  extracted_at: string;
  source: string;
  total_amount: number;
  date_range: DateRange;
  record_count: number;
  extraction_sources: number;
  schema_version: string;
}

export interface PipelineExtractInventoryResult {
  [key: string]: unknown;
  records: WarehouseRecord[];
  extracted_at: string;
  source: string;
  total_quantity: number;
  warehouses: string[];
  products_tracked: number;
  record_count: number;
  warehouse_count: number;
  include_archived: unknown;
}

export interface PipelineExtractCustomerResult {
  [key: string]: unknown;
  records: CustomerRecord[];
  extracted_at: string;
  source: string;
  total_customers: number;
  total_lifetime_value: number;
  tier_breakdown: Record<string, number>;
  avg_lifetime_value: number;
  active_customers: number;
  new_customers_in_period: number;
  churn_count: number;
  region_breakdown: Record<string, number>;
  date_range: DateRange;
}

export interface DailySalesEntry {
  total_amount: number;
  order_count: number;
  avg_order_value: number;
}

export interface ProductSalesEntry {
  total_quantity: number;
  total_revenue: number;
  order_count: number;
}

export interface PipelineTransformSalesResult {
  [key: string]: unknown;
  record_count: number;
  daily_sales: Record<string, DailySalesEntry>;
  product_sales: Record<string, ProductSalesEntry>;
  total_revenue: number;
  transformation_type: string;
  source: string;
  unique_categories: number;
  avg_transaction_value: number;
  transformed_at: string;
}

export interface WarehouseSummaryEntry {
  total_quantity: number;
  product_count: number;
  reorder_alerts: number;
}

export interface ProductInventoryEntry {
  total_quantity: number;
  warehouse_count: number;
  needs_reorder: boolean;
}

export interface PipelineTransformInventoryResult {
  [key: string]: unknown;
  record_count: number;
  warehouse_summary: Record<string, WarehouseSummaryEntry>;
  product_inventory: Record<string, ProductInventoryEntry>;
  total_quantity_on_hand: number;
  reorder_alerts: number;
  transformation_type: string;
  source: string;
  transformed_at: string;
}

export interface TierAnalysisEntry {
  customer_count: number;
  total_lifetime_value: number;
  avg_lifetime_value: number;
}

export interface PipelineTransformCustomersResult {
  [key: string]: unknown;
  record_count: number;
  tier_analysis: Record<string, TierAnalysisEntry>;
  value_segments: {
    high_value: number;
    medium_value: number;
    low_value: number;
  };
  total_lifetime_value: number;
  avg_customer_value: number;
  transformation_type: string;
  source: string;
  region_distribution: unknown;
  transformed_at: string;
}

export interface PipelineAggregateMetricsResult {
  [key: string]: unknown;
  total_revenue: number;
  total_inventory_quantity: number;
  total_customers: number;
  total_customer_lifetime_value: number;
  sales_transactions: number;
  inventory_reorder_alerts: number;
  revenue_per_customer: number;
  inventory_turnover_indicator: number;
  aggregation_complete: boolean;
  sources_included: number;
  aggregated_at: string;
}

export interface InsightEntry {
  category: string;
  finding: string;
  metric: number;
  recommendation: string;
}

export interface PipelineGenerateInsightsResult {
  [key: string]: unknown;
  insights: InsightEntry[];
  health_score: {
    score: number;
    max_score: number;
    rating: string;
  };
  total_metrics_analyzed: number;
  pipeline_complete: boolean;
  generated_at: string;
}

// ---------------------------------------------------------------------------
// Customer Success input types
// ---------------------------------------------------------------------------

export interface ValidateRefundRequestInput {
  ticketId: string;
  customerId: string;
  refundAmount: number;
  refundReason: string;
}

// ---------------------------------------------------------------------------
// Payments input types
// ---------------------------------------------------------------------------

export interface ValidatePaymentEligibilityInput {
  paymentId: string;
  refundAmount: number;
}

// ---------------------------------------------------------------------------
// Microservices input types
// ---------------------------------------------------------------------------

export interface CreateUserAccountInput {
  email: string;
  username: string;
  plan?: string;
  metadata?: Record<string, unknown>;
}

export interface BillingTier {
  price: number;
  features: string[];
  billing_required: boolean;
}

// ---------------------------------------------------------------------------
// Microservices result types
// ---------------------------------------------------------------------------

export interface MicroservicesCreateUserResult {
  [key: string]: unknown;
  user_id: string;
  email: string;
  name: string;
  plan: string;
  phone: null;
  source: string;
  status: string;
  created_at: string;
  api_key: string;
  auth_provider: string;
}

export interface MicroservicesSetupBillingActiveResult {
  [key: string]: unknown;
  billing_id: string;
  user_id: string;
  plan: string;
  price: number;
  currency: string;
  billing_cycle: string;
  features: string[];
  status: string;
  next_billing_date: string;
  created_at: string;
}

export interface MicroservicesSetupBillingSkippedResult {
  [key: string]: unknown;
  user_id: string;
  plan: string;
  billing_required: false;
  status: string;
  message: string;
}

export type MicroservicesSetupBillingResult =
  | MicroservicesSetupBillingActiveResult
  | MicroservicesSetupBillingSkippedResult;

export interface MicroservicesInitPreferencesResult {
  [key: string]: unknown;
  preferences_id: string;
  user_id: string;
  plan: string;
  preferences: Record<string, unknown>;
  defaults_applied: number;
  customizations: number;
  status: string;
  created_at: string;
  updated_at: string;
}

export interface MicroservicesSendWelcomeResult {
  [key: string]: unknown;
  user_id: string;
  plan: string;
  channels_used: string[];
  messages_sent: number;
  welcome_sequence_id: string;
  status: string;
  sent_at: string;
  recipient: string;
}

export interface MicroservicesUpdateStatusResult {
  [key: string]: unknown;
  user_id: string;
  status: string;
  plan: string;
  registration_summary: Record<string, unknown>;
  activation_timestamp: string;
  all_services_coordinated: boolean;
  services_completed: string[];
}

// ---------------------------------------------------------------------------
// Customer Success result types
// ---------------------------------------------------------------------------

export interface CustomerSuccessValidateRefundResult {
  [key: string]: unknown;
  request_validated: true;
  ticket_id: string | undefined;
  customer_id: string | undefined;
  ticket_status: string;
  customer_tier: string;
  original_purchase_date: string;
  payment_id: string;
  validation_timestamp: string;
  namespace: string;
}

export interface CustomerSuccessCheckRefundPolicyResult {
  [key: string]: unknown;
  policy_checked: true;
  policy_compliant: boolean;
  customer_tier: string;
  refund_window_days: number;
  days_since_purchase: number;
  within_refund_window: boolean;
  requires_approval: boolean;
  max_allowed_amount: number;
  policy_checked_at: string;
  namespace: string;
}

export interface CustomerSuccessApproveRefundResult {
  [key: string]: unknown;
  approval_obtained: true;
  approval_required: boolean;
  auto_approved: boolean;
  approval_id: string | null;
  manager_id: string | null;
  manager_notes: string;
  approved_at: string;
  namespace: string;
}

export interface CustomerSuccessExecuteRefundResult {
  [key: string]: unknown;
  task_delegated: true;
  target_namespace: string;
  target_workflow: string;
  delegated_task_id: string;
  delegated_task_status: string;
  delegation_timestamp: string;
  correlation_id: string;
  namespace: string;
}

export interface CustomerSuccessUpdateTicketResult {
  [key: string]: unknown;
  ticket_updated: true;
  ticket_id: string;
  previous_status: string;
  new_status: string;
  resolution_note: string;
  updated_at: string;
  refund_completed: boolean;
  delegated_task_id: string;
  namespace: string;
}

// ---------------------------------------------------------------------------
// Payments result types
// ---------------------------------------------------------------------------

export interface PaymentsValidateEligibilityResult {
  [key: string]: unknown;
  payment_validated: true;
  payment_id: string;
  original_amount: number;
  refund_amount: number;
  payment_method: string;
  gateway_provider: string;
  eligibility_status: string;
  validation_timestamp: string;
  namespace: string;
}

export interface PaymentsProcessGatewayResult {
  [key: string]: unknown;
  refund_processed: true;
  refund_id: string;
  payment_id: string;
  refund_amount: number;
  refund_status: string;
  gateway_transaction_id: string;
  gateway_provider: string;
  processed_at: string;
  estimated_arrival: string;
  namespace: string;
}

export interface PaymentsUpdateRecordsResult {
  [key: string]: unknown;
  records_updated: true;
  payment_id: string;
  refund_id: string;
  record_id: string;
  payment_status: string;
  refund_status: string;
  history_entries_created: number;
  updated_at: string;
  namespace: string;
}

export interface PaymentsNotifyCustomerResult {
  [key: string]: unknown;
  notification_sent: true;
  customer_email: string;
  message_id: string;
  notification_type: string;
  sent_at: string;
  delivery_status: string;
  refund_id: string;
  refund_amount: number;
  namespace: string;
}
