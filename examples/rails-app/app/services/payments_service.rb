# frozen_string_literal: true

# Service functions return Dry::Struct instances from Types::Payments.
# See Types::Payments in app/services/types.rb for full struct definitions.
#   validate_eligibility  -> Types::Payments::ValidateEligibilityResult
#   process_gateway       -> Types::Payments::ProcessGatewayResult
#   update_records        -> Types::Payments::UpdateRecordsResult
#   notify_customer       -> Types::Payments::NotifyCustomerResult
module Payments
  module Service
    SUPPORTED_CURRENCIES = %w[USD EUR GBP CAD AUD].freeze
    MAX_REFUND_AMOUNT = {
      'USD' => 50_000.00,
      'EUR' => 45_000.00,
      'GBP' => 40_000.00,
      'CAD' => 65_000.00,
      'AUD' => 75_000.00
    }.freeze
    REFUND_ELIGIBILITY_DAYS = 180

    module_function

    def validate_eligibility(input:)
      payment_id = input.payment_id
      currency = input.currency
      reason = input.reason
      idempotency_key = input.idempotency_key
      partial_refund = input.partial_refund

      amount = input.refund_amount.to_f
      raise TaskerCore::Errors::PermanentError.new(
        "Invalid refund amount: #{amount}",
        error_code: 'INVALID_AMOUNT'
      ) if amount <= 0

      unless SUPPORTED_CURRENCIES.include?(currency)
        raise TaskerCore::Errors::PermanentError.new(
          "Unsupported currency: #{currency}. Supported: #{SUPPORTED_CURRENCIES.join(', ')}",
          error_code: 'UNSUPPORTED_CURRENCY'
        )
      end

      max_amount = MAX_REFUND_AMOUNT[currency]
      if amount > max_amount
        raise TaskerCore::Errors::PermanentError.new(
          "Refund amount #{amount} #{currency} exceeds maximum of #{max_amount} #{currency}",
          error_code: 'EXCEEDS_MAX_AMOUNT'
        )
      end

      # Simulate original payment lookup
      original_amount = (amount + rand(0.0..200.0)).round(2)
      payment_date = Date.current - rand(1..365)
      days_since_payment = (Date.current - payment_date).to_i
      gateway = %w[stripe braintree adyen].sample

      # Check refund window
      within_window = days_since_payment <= REFUND_ELIGIBILITY_DAYS

      # Check for duplicate refund (idempotency)
      idempotency_key ||= "idem_#{SecureRandom.hex(16)}"
      is_duplicate = false # In real system, would check against stored keys

      # Simulate previous refunds on this payment
      previous_refund_total = (rand(0.0..[original_amount * 0.3, 0].max)).round(2)
      remaining_refundable = (original_amount - previous_refund_total).round(2)

      if amount > remaining_refundable
        raise TaskerCore::Errors::PermanentError.new(
          "Refund amount #{amount} exceeds remaining refundable balance of #{remaining_refundable} #{currency}",
          error_code: 'EXCEEDS_REFUNDABLE_BALANCE'
        )
      end

      eligibility_id = "elig_#{SecureRandom.hex(8)}"

      Types::Payments::ValidateEligibilityResult.new(
        payment_validated: true,
        payment_id: payment_id,
        original_amount: original_amount,
        refund_amount: amount,
        payment_method: 'credit_card',
        gateway_provider: gateway,
        eligibility_status: (within_window && !is_duplicate) ? 'eligible' : 'ineligible',
        validation_timestamp: Time.current.iso8601,
        namespace: 'payments_rb',
        eligibility_id: eligibility_id,
        eligible: within_window && !is_duplicate,
        currency: currency,
        reason: reason,
        original_payment: {
          amount: original_amount,
          date: payment_date.iso8601,
          gateway: gateway,
          status: 'captured',
          days_since_payment: days_since_payment
        },
        refund_history: {
          previous_refund_total: previous_refund_total,
          remaining_refundable: remaining_refundable,
          refund_count: previous_refund_total > 0 ? rand(1..3) : 0
        },
        idempotency_key: idempotency_key,
        is_duplicate: is_duplicate,
        within_refund_window: within_window,
        validated_at: Time.current.iso8601
      )
    end

    def process_gateway(eligibility:, refund_reason:, partial_refund:)
      raise TaskerCore::Errors::PermanentError.new(
        'Eligibility data not available',
        error_code: 'MISSING_ELIGIBILITY'
      ) if eligibility.nil?

      unless eligibility['eligible'] || eligibility['payment_validated']
        raise TaskerCore::Errors::PermanentError.new(
          'Payment is not eligible for refund',
          error_code: 'NOT_ELIGIBLE'
        )
      end

      amount = (eligibility['refund_amount']).to_f
      currency = eligibility['currency']
      gateway = eligibility.dig('original_payment', 'gateway') || eligibility['gateway_provider'] || 'unknown'
      idempotency_key = eligibility['idempotency_key']

      # Simulate gateway-specific processing
      gateway_request_id = "gw_req_#{SecureRandom.hex(12)}"
      processing_started_at = Time.current

      # Simulate potential gateway issues
      if gateway == 'unknown'
        raise TaskerCore::Errors::RetryableError.new(
          'Unable to determine payment gateway - retrying'
        )
      end

      # Simulate gateway response
      gateway_transaction_id = case gateway
                               when 'stripe'    then "re_#{SecureRandom.hex(12)}"
                               when 'braintree' then "bt_rfnd_#{SecureRandom.hex(8)}"
                               when 'adyen'     then "ADY-#{SecureRandom.hex(10).upcase}"
                               end

      processing_time_ms = rand(200..3000)
      processing_completed_at = processing_started_at + (processing_time_ms / 1000.0)

      # Determine settlement timeline based on gateway
      settlement_days = case gateway
                        when 'stripe'    then rand(5..10)
                        when 'braintree' then rand(3..7)
                        when 'adyen'     then rand(5..14)
                        end

      estimated_settlement = (Date.current + settlement_days)

      # Calculate any gateway fees
      gateway_fee_rate = case gateway
                         when 'stripe'    then 0.0025
                         when 'braintree' then 0.0020
                         when 'adyen'     then 0.0030
                         end
      gateway_fee = (amount * gateway_fee_rate).round(2)
      net_refund = (amount - gateway_fee).round(2)

      refund_id = "rfnd_#{SecureRandom.hex(8)}"

      Types::Payments::ProcessGatewayResult.new(
        refund_processed: true,
        refund_id: refund_id,
        payment_id: eligibility['payment_id'],
        refund_amount: amount,
        refund_status: 'processed',
        gateway_transaction_id: gateway_transaction_id,
        gateway_provider: gateway,
        processed_at: processing_completed_at.iso8601,
        estimated_arrival: estimated_settlement.iso8601,
        namespace: 'payments_rb',
        gateway_request_id: gateway_request_id,
        gateway: gateway,
        gateway_fee: gateway_fee,
        net_refund_amount: net_refund,
        currency: currency,
        status: 'processed',
        idempotency_key: idempotency_key,
        processing_time_ms: processing_time_ms,
        settlement: {
          estimated_days: settlement_days,
          estimated_date: estimated_settlement.iso8601,
          method: eligibility.dig('original_payment', 'status') == 'captured' ? 'original_method' : 'account_credit'
        },
        gateway_response: {
          code: '200',
          message: 'Refund processed successfully',
          raw_response_id: "resp_#{SecureRandom.hex(8)}"
        }
      )
    end

    def update_records(eligibility:, gateway_result:, refund_reason:)
      raise TaskerCore::Errors::PermanentError.new(
        'Upstream data not available for record update',
        error_code: 'MISSING_DEPENDENCIES'
      ) if eligibility.nil? || gateway_result.nil?

      payment_id = gateway_result['payment_id'] || eligibility['payment_id']
      refund_id = gateway_result['refund_id']
      amount = (gateway_result['refund_amount']).to_f
      currency = gateway_result['currency']
      gateway_transaction_id = gateway_result['gateway_transaction_id']

      record_update_id = "rec_#{SecureRandom.hex(8)}"

      # Simulate updating multiple internal systems
      records_updated = []

      # 1. Payment ledger entry
      ledger_entry_id = "led_#{SecureRandom.hex(10)}"
      records_updated << {
        system: 'payment_ledger',
        record_id: ledger_entry_id,
        entry_type: 'refund',
        debit_account: 'refunds_payable',
        credit_account: 'customer_receivable',
        amount: amount,
        currency: currency,
        reference: gateway_transaction_id,
        status: 'posted',
        updated_at: Time.current.iso8601
      }

      # 2. Transaction history
      records_updated << {
        system: 'transaction_history',
        record_id: "txh_#{SecureRandom.hex(8)}",
        payment_id: payment_id,
        type: 'refund',
        amount: -amount,
        running_balance: (eligibility.dig('refund_history', 'remaining_refundable').to_f - amount).round(2),
        status: 'completed',
        updated_at: Time.current.iso8601
      }

      # 3. Revenue adjustment
      records_updated << {
        system: 'revenue_tracking',
        record_id: "rev_#{SecureRandom.hex(8)}",
        adjustment_type: 'refund_reversal',
        amount: -amount,
        period: Date.current.strftime('%Y-%m'),
        impact: 'negative',
        updated_at: Time.current.iso8601
      }

      # 4. Gateway fee tracking
      gateway_fee = gateway_result['gateway_fee'].to_f
      if gateway_fee > 0
        records_updated << {
          system: 'fee_tracking',
          record_id: "fee_#{SecureRandom.hex(8)}",
          fee_type: 'refund_processing',
          gateway: gateway_result['gateway'],
          amount: gateway_fee,
          currency: currency,
          updated_at: Time.current.iso8601
        }
      end

      # 5. Reconciliation record
      records_updated << {
        system: 'reconciliation',
        record_id: "recon_#{SecureRandom.hex(8)}",
        payment_id: payment_id,
        gateway_ref: gateway_transaction_id,
        expected_settlement_date: gateway_result.dig('settlement', 'estimated_date'),
        status: 'pending_settlement',
        updated_at: Time.current.iso8601
      }

      all_successful = records_updated.all? { |r| %w[posted completed pending_settlement].include?(r[:status]) }

      record_id = "rec_#{SecureRandom.hex(8)}"

      Types::Payments::UpdateRecordsResult.new(
        records_updated: true,
        payment_id: payment_id,
        refund_id: refund_id,
        record_id: record_id,
        payment_status: 'refunded',
        refund_status: 'completed',
        history_entries_created: records_updated.size,
        updated_at: Time.current.iso8601,
        namespace: 'payments_rb',
        record_update_id: record_update_id,
        records_updated_details: records_updated,
        total_records: records_updated.size,
        all_successful: all_successful,
        ledger_entry_id: ledger_entry_id,
        accounting_impact: {
          gross_refund: amount,
          gateway_fee: gateway_fee,
          net_impact: (amount - gateway_fee).round(2),
          period: Date.current.strftime('%Y-%m')
        }
      )
    end

    def notify_customer(eligibility:, gateway_result:, records_result:, customer_email:, refund_reason:)
      raise TaskerCore::Errors::PermanentError.new(
        'Upstream data not available for customer notification',
        error_code: 'MISSING_DEPENDENCIES'
      ) if eligibility.nil? || gateway_result.nil? || records_result.nil?

      payment_id = gateway_result['payment_id'] || eligibility['payment_id']
      amount = (gateway_result['refund_amount']).to_f
      currency = gateway_result['currency']
      settlement = gateway_result['settlement'] || {}
      reason = refund_reason || eligibility['reason'] || 'refund_processed'
      refund_id = gateway_result['refund_id']

      notification_id = "notif_#{SecureRandom.hex(10)}"
      sent_at = Time.current

      # Build customer-facing notification content
      formatted_amount = "#{currency} #{'%.2f' % amount}"
      settlement_message = if settlement['estimated_days']
                             "Please allow #{settlement['estimated_days']} business days for the refund to appear on your statement."
                           else
                             'Your refund will be processed within the standard settlement period.'
                           end

      # Send through multiple channels
      notifications = []

      # Email notification
      email_message_id = "email_#{SecureRandom.hex(12)}"
      notifications << {
        channel: 'email',
        message_id: email_message_id,
        subject: "Refund Processed - #{formatted_amount}",
        body_preview: "Your refund of #{formatted_amount} for payment #{payment_id} has been processed. #{settlement_message}",
        template: 'refund_confirmation',
        template_variables: {
          amount: formatted_amount,
          payment_id: payment_id,
          settlement_message: settlement_message,
          reason: reason.humanize,
          support_url: 'https://support.example.com/refunds'
        },
        status: 'sent',
        sent_at: sent_at.iso8601
      }

      # Push notification
      notifications << {
        channel: 'push',
        message_id: "push_#{SecureRandom.hex(8)}",
        title: 'Refund Processed',
        body: "Your refund of #{formatted_amount} has been processed.",
        action: 'view_payment_details',
        action_data: { payment_id: payment_id },
        status: 'delivered',
        sent_at: sent_at.iso8601
      }

      # In-app notification
      notifications << {
        channel: 'in_app',
        message_id: "inapp_#{SecureRandom.hex(8)}",
        title: 'Refund Confirmed',
        body: "#{formatted_amount} refund for payment #{payment_id}. #{settlement_message}",
        category: 'payment',
        priority: 'normal',
        action_url: "/payments/#{payment_id}/refunds",
        expires_at: (sent_at + 30.days).iso8601,
        status: 'created',
        sent_at: sent_at.iso8601
      }

      # Webhook notification (for API integrations)
      notifications << {
        channel: 'webhook',
        message_id: "wh_#{SecureRandom.hex(8)}",
        event_type: 'payment.refunded',
        payload: {
          payment_id: payment_id,
          refund_amount: amount,
          currency: currency,
          gateway_transaction_id: gateway_result['gateway_transaction_id'],
          status: 'processed',
          timestamp: sent_at.iso8601
        },
        status: 'dispatched',
        sent_at: sent_at.iso8601
      }

      all_sent = notifications.all? { |n| %w[sent delivered created dispatched].include?(n[:status]) }

      message_id = email_message_id

      Types::Payments::NotifyCustomerResult.new(
        notification_sent: true,
        customer_email: customer_email || 'customer@example.com',
        message_id: message_id,
        notification_type: 'refund_confirmation',
        sent_at: sent_at.iso8601,
        delivery_status: all_sent ? 'delivered' : 'partial',
        refund_id: refund_id,
        refund_amount: amount,
        namespace: 'payments_rb',
        notification_id: notification_id,
        payment_id: payment_id,
        currency: currency,
        notifications: notifications,
        total_notifications: notifications.size,
        all_sent: all_sent,
        channels_used: notifications.map { |n| n[:channel] },
        settlement_info: {
          estimated_days: settlement['estimated_days'],
          estimated_date: settlement['estimated_date'],
          method: settlement['method']
        },
        notified_at: sent_at.iso8601
      )
    end
  end
end
