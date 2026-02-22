# frozen_string_literal: true

require 'dry-struct'
require 'dry-types'

# Shared type definitions for all service modules.
#
# Input types describe what flows into service functions.
# Result types describe what each service function returns — the contract
# that downstream steps read via dependency injection.
#
# Services return Dry::Struct instances constructed from these result types.
# All result struct attributes are optional and omittable (via ResultStruct)
# so that construction works gracefully even when some keys are absent.
module Types
  include Dry.Types()

  # Base class for result types used with model-based dependency injection.
  # All attributes are optional and omittable so that model_cls.new(**data)
  # works gracefully even when the result hash has missing keys.
  class ResultStruct < Dry::Struct
    transform_types do |type|
      if type.default?
        type
      else
        type.optional.omittable
      end
    end

    # Allow both string and symbol key access so that service code using
    # hash-style access (e.g., result['user_id']) works with Dry::Struct
    # attributes which are stored as symbols internally.
    def [](name)
      key = name.respond_to?(:to_sym) ? name.to_sym : name
      return nil unless self.class.attribute_names.include?(key)

      super(key)
    end

    # Enable nested access via dig, e.g. validation.dig('order_data', 'payment_method')
    def dig(key, *rest)
      value = self[key]
      if rest.empty? || value.nil?
        value
      else
        value.dig(*rest)
      end
    end
  end

  # Base class for input types that receive the full task context hash.
  # Like ResultStruct, all attributes are optional and omittable so that
  # missing keys don't raise — handlers validate required fields explicitly.
  class InputStruct < Dry::Struct
    transform_types do |type|
      if type.default?
        type
      else
        type.optional.omittable
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Customer Success input types
  # ---------------------------------------------------------------------------

  module CustomerSuccess
    class ValidateRefundRequestInput < Types::InputStruct
      attribute :ticket_id, Types::String.optional
      attribute :order_ref, Types::String.optional
      attribute :customer_id, Types::String.optional
      attribute :refund_amount, Types::Float.optional
      attribute :refund_reason, Types::String.optional
      attribute :reason, Types::String.optional
      attribute :correlation_id, Types::String.optional
      attribute :agent_id, Types::String.optional
      attribute :priority, Types::String.optional

      # Resolve refund_reason from either field name (controller sends 'reason')
      def resolved_refund_reason
        refund_reason || reason
      end

      # Input validation — required fields are enforced at the model level.
      def validate!
        missing = []
        missing << 'ticket_id' if ticket_id.blank?
        missing << 'customer_id' if customer_id.blank?
        missing << 'refund_amount' if refund_amount.nil?
        missing << 'refund_reason' if resolved_refund_reason.blank?
        return if missing.empty?

        raise TaskerCore::Errors::PermanentError.new(
          "Missing required fields: #{missing.join(', ')}",
          error_code: 'MISSING_FIELDS'
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Payments input types
  # ---------------------------------------------------------------------------

  module Payments
    class ValidateEligibilityInput < Types::InputStruct
      attribute :payment_id, Types::String.optional
      attribute :refund_amount, Types::Float.optional
      attribute :currency, Types::String.optional
      attribute :reason, Types::String.optional
      attribute :refund_reason, Types::String.optional
      attribute :idempotency_key, Types::String.optional
      attribute :partial_refund, Types::Bool.optional
      attribute :customer_email, Types::String.optional

      # Resolve refund_reason from either field name (controller sends 'reason')
      def resolved_refund_reason
        refund_reason || reason
      end

      # Input validation — required fields are enforced at the model level.
      def validate!
        missing = []
        missing << 'payment_id' if payment_id.blank?
        missing << 'refund_amount' if refund_amount.nil?
        return if missing.empty?

        raise TaskerCore::Errors::PermanentError.new(
          "Missing required fields: #{missing.join(', ')}",
          error_code: 'MISSING_FIELDS'
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Microservices input types
  # ---------------------------------------------------------------------------

  module Microservices
    class CreateUserAccountInput < Types::InputStruct
      attribute :email, Types::String.optional
      attribute :name, Types::String.optional
      attribute :plan, Types::String.optional
      attribute :referral_code, Types::String.optional
      attribute :marketing_consent, Types::Bool.optional

      # Input validation — required fields are enforced at the model level.
      def validate!
        missing = []
        missing << 'email' if email.blank?
        missing << 'name' if name.blank?
        return if missing.empty?

        raise TaskerCore::Errors::PermanentError.new(
          "Missing required fields: #{missing.join(', ')}",
          error_code: 'MISSING_FIELDS'
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Ecommerce result types
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Ecommerce input types
  # ---------------------------------------------------------------------------

  module Ecommerce
    class OrderInput < Types::InputStruct
      attribute :cart_items, Types::Array.optional
      attribute :customer_email, Types::String.optional
      attribute :payment_info, Types::Hash.optional
      attribute :shipping_address, Types::Hash.optional
      attribute :customer_info, Types::Hash.optional
    end
  end

  # ---------------------------------------------------------------------------
  # Data Pipeline input types
  # ---------------------------------------------------------------------------

  module DataPipeline
    class PipelineInput < Types::InputStruct
      attribute :source, Types::String.optional
      attribute :date_range_start, Types::String.optional
      attribute :date_range_end, Types::String.optional
      attribute :date_range, Types::Hash.optional
      attribute :granularity, Types::String.optional
      attribute :filters, Types::Hash.optional

      # Resolve date_range_start from flat field or nested date_range hash
      def resolved_date_range_start
        date_range_start || date_range&.dig('start_date') || date_range&.dig(:start_date)
      end

      # Resolve date_range_end from flat field or nested date_range hash
      def resolved_date_range_end
        date_range_end || date_range&.dig('end_date') || date_range&.dig(:end_date)
      end
    end
  end

  module Ecommerce
    class ValidateCartResult < Types::ResultStruct
      attribute :validated_items, Types::Array
      attribute :item_count, Types::Integer
      attribute :subtotal, Types::Float
      attribute :tax, Types::Float
      attribute :tax_rate, Types::Float
      attribute :shipping, Types::Float
      attribute :total, Types::Float
      attribute :free_shipping, Types::Bool
      attribute :validation_id, Types::String
      attribute :validated_at, Types::String
    end

    class ProcessPaymentResult < Types::ResultStruct
      attribute :payment_id, Types::String
      attribute :transaction_id, Types::String
      attribute :authorization_code, Types::String
      attribute :amount_charged, Types::Float
      attribute :currency, Types::String
      attribute :payment_method_type, Types::String
      attribute :last_four, Types::String
      attribute :status, Types::String
      attribute :gateway_response_code, Types::String
      attribute :processed_at, Types::String
    end

    class UpdateInventoryResult < Types::ResultStruct
      attribute :updated_products, Types::Array
      attribute :total_items_reserved, Types::Integer
      attribute :inventory_changes, Types::Array
      attribute :inventory_log_id, Types::String
      attribute :updated_at, Types::String
      attribute :reservation_id, Types::String
      attribute :reservation_expires_at, Types::String
      attribute :all_items_reserved, Types::Bool
    end

    class CreateOrderResult < Types::ResultStruct
      attribute :order_id, Types::String
      attribute :order_number, Types::String
      attribute :status, Types::String
      attribute :total_amount, Types::Float
      attribute :customer_email, Types::String
      attribute :created_at, Types::String
      attribute :estimated_delivery, Types::String
      attribute :items, Types::Array
      attribute :subtotal, Types::Float
      attribute :tax, Types::Float
      attribute :shipping, Types::Float
      attribute :payment, Types::Hash
      attribute :inventory, Types::Hash
      attribute :shipping_address, Types::Hash.optional
      attribute :estimated_shipping_days, Types::Integer
    end

    class SendConfirmationResult < Types::ResultStruct
      attribute :email_sent, Types::Bool
      attribute :recipient, Types::String
      attribute :email_type, Types::String
      attribute :sent_at, Types::String
      attribute :message_id, Types::String
      attribute :order_id, Types::String
      attribute :notifications_sent, Types::Array
      attribute :email_subject, Types::String
      attribute :email_body_preview, Types::String
      attribute :total_channels, Types::Integer
      attribute :all_delivered, Types::Bool
      attribute :confirmation_sent_at, Types::String
    end
  end

  # ---------------------------------------------------------------------------
  # Data Pipeline result types
  # ---------------------------------------------------------------------------

  module DataPipeline
    class ExtractSalesResult < Types::ResultStruct
      attribute :source, Types::String
      attribute :extraction_id, Types::String
      attribute :date_range, Types::Hash
      attribute :record_count, Types::Integer
      attribute :records, Types::Array
      attribute :total_amount, Types::Float
      attribute :total_revenue, Types::Float
      attribute :extracted_at, Types::String
    end

    class ExtractInventoryResult < Types::ResultStruct
      attribute :source, Types::String
      attribute :extraction_id, Types::String
      attribute :record_count, Types::Integer
      attribute :records, Types::Array
      attribute :total_quantity, Types::Integer
      attribute :warehouses, Types::Array.of(Types::String)
      attribute :products_tracked, Types::Integer
      attribute :total_inventory_value, Types::Float
      attribute :items_needing_reorder, Types::Integer
      attribute :warehouses_covered, Types::Array.of(Types::String)
      attribute :extracted_at, Types::String
    end

    class ExtractCustomerResult < Types::ResultStruct
      attribute :source, Types::String
      attribute :extraction_id, Types::String
      attribute :record_count, Types::Integer
      attribute :records, Types::Array
      attribute :total_customers, Types::Integer
      attribute :total_lifetime_value, Types::Float
      attribute :tier_breakdown, Types::Hash
      attribute :avg_lifetime_value, Types::Float
      attribute :average_lifetime_value, Types::Float
      attribute :segment_distribution, Types::Hash
      attribute :engagement_rate, Types::Float
      attribute :extracted_at, Types::String
    end

    class TransformSalesResult < Types::ResultStruct
      attribute :record_count, Types::Integer
      attribute :daily_sales, Types::Hash
      attribute :product_sales, Types::Hash
      attribute :total_revenue, Types::Float
      attribute :transformation_type, Types::String
      attribute :source, Types::String
      attribute :transform_id, Types::String
      attribute :source_record_count, Types::Integer
      attribute :product_metrics, Types::Array
      attribute :region_metrics, Types::Array
      attribute :channel_metrics, Types::Array
      attribute :top_product, Types::String.optional
      attribute :top_region, Types::String.optional
      attribute :transformed_at, Types::String
    end

    class TransformInventoryResult < Types::ResultStruct
      attribute :record_count, Types::Integer
      attribute :warehouse_summary, Types::Hash
      attribute :product_inventory, Types::Hash
      attribute :total_quantity_on_hand, Types::Integer
      attribute :reorder_alerts, Types::Integer
      attribute :transformation_type, Types::String
      attribute :source, Types::String
      attribute :transform_id, Types::String
      attribute :source_record_count, Types::Integer
      attribute :category_metrics, Types::Array
      attribute :warehouse_metrics, Types::Array
      attribute :total_inventory_value, Types::Float
      attribute :total_skus, Types::Integer
      attribute :transformed_at, Types::String
    end

    class TransformCustomersResult < Types::ResultStruct
      attribute :record_count, Types::Integer
      attribute :tier_analysis, Types::Hash
      attribute :value_segments, Types::Hash
      attribute :total_lifetime_value, Types::Float
      attribute :avg_customer_value, Types::Float
      attribute :transformation_type, Types::String
      attribute :source, Types::String
      attribute :transform_id, Types::String
      attribute :source_record_count, Types::Integer
      attribute :segment_metrics, Types::Array
      attribute :tier_metrics, Types::Array
      attribute :channel_metrics, Types::Array
      attribute :region_metrics, Types::Array
      attribute :churn_risk_rate, Types::Float
      attribute :at_risk_customer_count, Types::Integer
      attribute :overall_engagement_rate, Types::Float
      attribute :transformed_at, Types::String
    end

    class AggregateMetricsResult < Types::ResultStruct
      attribute :total_revenue, Types::Float
      attribute :total_inventory_quantity, Types::Float
      attribute :total_customers, Types::Integer
      attribute :total_customer_lifetime_value, Types::Float
      attribute :sales_transactions, Types::Integer
      attribute :inventory_reorder_alerts, Types::Integer
      attribute :revenue_per_customer, Types::Float
      attribute :inventory_turnover_indicator, Types::Float
      attribute :aggregation_complete, Types::Bool
      attribute :sources_included, Types::Integer
      attribute :aggregation_id, Types::String
      attribute :summary, Types::Hash
      attribute :health_scores, Types::Hash
      attribute :highlights, Types::Hash
      attribute :breakdowns, Types::Hash
      attribute :data_sources, Types::Hash
      attribute :aggregated_at, Types::String
    end

    class GenerateInsightsResult < Types::ResultStruct
      attribute :insights, Types::Array
      attribute :health_score, Types::Hash
      attribute :total_metrics_analyzed, Types::Integer
      attribute :pipeline_complete, Types::Bool
      attribute :generated_at, Types::String
      attribute :report_id, Types::String
      attribute :business_health, Types::String
      attribute :overall_score, Types::Integer
      attribute :component_scores, Types::Hash
      attribute :recommendations, Types::Array
      attribute :insight_count, Types::Integer
      attribute :recommendation_count, Types::Integer
      attribute :critical_items, Types::Integer
      attribute :data_freshness, Types::String
    end
  end

  # ---------------------------------------------------------------------------
  # Microservices result types
  # ---------------------------------------------------------------------------

  module Microservices
    class CreateUserResult < Types::ResultStruct
      attribute :user_id, Types::String
      attribute :username, Types::String
      attribute :email, Types::String
      attribute :name, Types::String
      attribute :plan, Types::String
      attribute :referral_code, Types::String.optional
      attribute :referral_valid, Types::Bool
      attribute :status, Types::String
      attribute :account_status, Types::String
      attribute :email_verified, Types::Bool
      attribute :verification_token, Types::String
      attribute :created_at, Types::String
    end

    class SetupBillingResult < Types::ResultStruct
      attribute :billing_id, Types::String
      attribute :subscription_id, Types::String
      attribute :user_id, Types::String
      attribute :plan, Types::String
      attribute :billing_cycle, Types::String
      attribute :monthly_price, Types::Float
      attribute :annual_price, Types::Float
      attribute :currency, Types::String
      attribute :features, Types::Array.of(Types::String)
      attribute :trial_days, Types::Integer
      attribute :trial_end_date, Types::String.optional
      attribute :payment_method_required, Types::Bool
      attribute :next_billing_date, Types::String
      attribute :price, Types::Float
      attribute :status, Types::String
      attribute :billing_status, Types::String
      attribute :created_at, Types::String
    end

    class InitPreferencesResult < Types::ResultStruct
      attribute :preferences_id, Types::String
      attribute :user_id, Types::String
      attribute :plan, Types::String
      attribute :preferences, Types::Hash
      attribute :defaults_applied, Types::Integer
      attribute :customizations, Types::Integer
      attribute :status, Types::String
      attribute :created_at, Types::String
      attribute :updated_at, Types::String
      attribute :feature_flags, Types::Hash
      attribute :quotas, Types::Hash
      attribute :initialized_at, Types::String
    end

    class SendWelcomeResult < Types::ResultStruct
      attribute :user_id, Types::String
      attribute :plan, Types::String
      attribute :channels_used, Types::Array.of(Types::String)
      attribute :messages_sent, Types::Integer
      attribute :welcome_sequence_id, Types::String
      attribute :status, Types::String
      attribute :sent_at, Types::String
      attribute :sequence_id, Types::String
      attribute :email, Types::String
      attribute :notifications_sent, Types::Array
      attribute :total_notifications, Types::Integer
      attribute :all_delivered, Types::Bool
      attribute :drip_campaign, Types::Hash
      attribute :welcome_sequence_completed_at, Types::String
    end

    class UpdateStatusResult < Types::ResultStruct
      attribute :user_id, Types::String
      attribute :status, Types::String
      attribute :plan, Types::String
      attribute :registration_summary, Types::Hash
      attribute :activation_timestamp, Types::String
      attribute :all_services_coordinated, Types::Bool
      attribute :services_completed, Types::Array.of(Types::String)
      attribute :registration_complete, Types::Bool
      attribute :registration_steps, Types::Hash
      attribute :onboarding_score, Types::Integer
      attribute :profile_summary, Types::Hash
      attribute :next_steps, Types::Array.of(Types::String)
      attribute :activated_at, Types::String
    end
  end

  # ---------------------------------------------------------------------------
  # Customer Success result types
  # ---------------------------------------------------------------------------

  module CustomerSuccess
    class ValidateRefundResult < Types::ResultStruct
      attribute :request_validated, Types::Bool
      attribute :ticket_id, Types::String
      attribute :customer_id, Types::String
      attribute :ticket_status, Types::String
      attribute :customer_tier, Types::String
      attribute :original_purchase_date, Types::String
      attribute :payment_id, Types::String
      attribute :validation_timestamp, Types::String
      attribute :namespace, Types::String
      attribute :validation_id, Types::String
      attribute :order_ref, Types::String
      attribute :refund_amount, Types::Float
      attribute :reason, Types::String
      attribute :order_data, Types::Hash
      attribute :refund_percentage, Types::Float
      attribute :is_partial_refund, Types::Bool
      attribute :is_valid, Types::Bool
      attribute :validated_at, Types::String
    end

    class CheckPolicyResult < Types::ResultStruct
      attribute :policy_checked, Types::Bool
      attribute :policy_compliant, Types::Bool
      attribute :customer_tier, Types::String
      attribute :refund_window_days, Types::Integer
      attribute :days_since_purchase, Types::Integer
      attribute :within_refund_window, Types::Bool
      attribute :requires_approval, Types::Bool
      attribute :max_allowed_amount, Types::Float
      attribute :policy_checked_at, Types::String
      attribute :namespace, Types::String
      attribute :check_id, Types::String
      attribute :policy_passed, Types::Bool
      attribute :violations, Types::Array.of(Types::String)
      attribute :warnings, Types::Array.of(Types::String)
      attribute :auto_approve, Types::Bool
      attribute :requires_manager_approval, Types::Bool
      attribute :approval_level, Types::String
      attribute :applied_policy, Types::Hash
      attribute :checked_at, Types::String
    end

    class ApproveRefundResult < Types::ResultStruct
      attribute :approval_obtained, Types::Bool
      attribute :approval_required, Types::Bool
      attribute :auto_approved, Types::Bool
      attribute :approval_id, Types::String.optional
      attribute :manager_id, Types::String.optional
      attribute :manager_notes, Types::String
      attribute :approved_at, Types::String
      attribute :namespace, Types::String
      attribute :approved, Types::Bool
      attribute :reason, Types::String
      attribute :denial_reason, Types::String
      attribute :approval_level, Types::String
      attribute :decision_type, Types::String
      attribute :decided_by, Types::String
      attribute :manager, Types::Hash
      attribute :requesting_agent, Types::String
      attribute :priority, Types::String
      attribute :conditions, Types::Array.of(Types::String)
      attribute :decided_at, Types::String
    end

    class ExecuteRefundResult < Types::ResultStruct
      attribute :task_delegated, Types::Bool
      attribute :target_namespace, Types::String
      attribute :target_workflow, Types::String
      attribute :delegated_task_id, Types::String
      attribute :delegated_task_status, Types::String
      attribute :delegation_timestamp, Types::String
      attribute :correlation_id, Types::String
      attribute :namespace, Types::String
      attribute :execution_id, Types::String
      attribute :executed, Types::Bool
      attribute :refund_transaction_id, Types::String
      attribute :amount_refunded, Types::Float
      attribute :order_ref, Types::String
      attribute :customer_id, Types::String
      attribute :payment_method, Types::String
      attribute :steps_executed, Types::Array
      attribute :total_steps, Types::Integer
      attribute :all_steps_completed, Types::Bool
      attribute :conditions_applied, Types::Array.of(Types::String)
      attribute :executed_at, Types::String
    end

    class UpdateTicketResult < Types::ResultStruct
      attribute :ticket_updated, Types::Bool
      attribute :ticket_id, Types::String
      attribute :previous_status, Types::String
      attribute :new_status, Types::String
      attribute :resolution_note, Types::String
      attribute :updated_at, Types::String
      attribute :refund_completed, Types::Bool
      attribute :delegated_task_id, Types::String
      attribute :namespace, Types::String
      attribute :update_id, Types::String
      attribute :ticket_status, Types::String
      attribute :resolution_category, Types::String
      attribute :timeline, Types::Array
      attribute :internal_notes, Types::String
      attribute :customer_facing_message, Types::String
      attribute :satisfaction_survey_scheduled, Types::Bool
      attribute :follow_up_required, Types::Bool
    end
  end

  # ---------------------------------------------------------------------------
  # Payments result types
  # ---------------------------------------------------------------------------

  module Payments
    class ValidateEligibilityResult < Types::ResultStruct
      attribute :payment_validated, Types::Bool
      attribute :payment_id, Types::String
      attribute :original_amount, Types::Float
      attribute :refund_amount, Types::Float
      attribute :payment_method, Types::String
      attribute :gateway_provider, Types::String
      attribute :eligibility_status, Types::String
      attribute :validation_timestamp, Types::String
      attribute :namespace, Types::String
      attribute :eligibility_id, Types::String
      attribute :eligible, Types::Bool
      attribute :currency, Types::String
      attribute :reason, Types::String
      attribute :original_payment, Types::Hash
      attribute :refund_history, Types::Hash
      attribute :idempotency_key, Types::String
      attribute :is_duplicate, Types::Bool
      attribute :within_refund_window, Types::Bool
      attribute :validated_at, Types::String
    end

    class ProcessGatewayResult < Types::ResultStruct
      attribute :refund_processed, Types::Bool
      attribute :refund_id, Types::String
      attribute :payment_id, Types::String
      attribute :refund_amount, Types::Float
      attribute :refund_status, Types::String
      attribute :gateway_transaction_id, Types::String
      attribute :gateway_provider, Types::String
      attribute :processed_at, Types::String
      attribute :estimated_arrival, Types::String
      attribute :namespace, Types::String
      attribute :gateway_request_id, Types::String
      attribute :gateway, Types::String
      attribute :gateway_fee, Types::Float
      attribute :net_refund_amount, Types::Float
      attribute :currency, Types::String
      attribute :status, Types::String
      attribute :idempotency_key, Types::String
      attribute :processing_time_ms, Types::Integer
      attribute :settlement, Types::Hash
      attribute :gateway_response, Types::Hash
    end

    class UpdateRecordsResult < Types::ResultStruct
      attribute :records_updated, Types::Bool
      attribute :payment_id, Types::String
      attribute :refund_id, Types::String
      attribute :record_id, Types::String
      attribute :payment_status, Types::String
      attribute :refund_status, Types::String
      attribute :history_entries_created, Types::Integer
      attribute :updated_at, Types::String
      attribute :namespace, Types::String
      attribute :record_update_id, Types::String
      attribute :records_updated_details, Types::Array
      attribute :total_records, Types::Integer
      attribute :all_successful, Types::Bool
      attribute :ledger_entry_id, Types::String
      attribute :accounting_impact, Types::Hash
    end

    class NotifyCustomerResult < Types::ResultStruct
      attribute :notification_sent, Types::Bool
      attribute :customer_email, Types::String
      attribute :message_id, Types::String
      attribute :notification_type, Types::String
      attribute :sent_at, Types::String
      attribute :delivery_status, Types::String
      attribute :refund_id, Types::String
      attribute :refund_amount, Types::Float
      attribute :namespace, Types::String
      attribute :notification_id, Types::String
      attribute :payment_id, Types::String
      attribute :currency, Types::String
      attribute :notifications, Types::Array
      attribute :total_notifications, Types::Integer
      attribute :all_sent, Types::Bool
      attribute :channels_used, Types::Array.of(Types::String)
      attribute :settlement_info, Types::Hash
      attribute :notified_at, Types::String
    end
  end
end
