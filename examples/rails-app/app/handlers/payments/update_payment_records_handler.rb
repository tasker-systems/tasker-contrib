module Payments
  module StepHandlers
    class UpdatePaymentRecordsHandler < TaskerCore::StepHandler::Base
      def call(context)
        # TAS-137: Use get_dependency_result() for upstream step results (auto-unwraps)
        eligibility = context.get_dependency_result('validate_payment_eligibility')
        eligibility = eligibility&.is_a?(Hash) ? eligibility : nil
        gateway_result = context.get_dependency_result('process_gateway_refund')
        gateway_result = gateway_result&.is_a?(Hash) ? gateway_result : nil

        # TAS-137: Use get_dependency_field() for nested field extraction
        payment_id = context.get_dependency_field('process_gateway_refund', 'payment_id')
        refund_id = context.get_dependency_field('process_gateway_refund', 'refund_id')
        refund_amount_dep = context.get_dependency_field('process_gateway_refund', 'refund_amount')
        gateway_transaction_id = context.get_dependency_field('process_gateway_refund', 'gateway_transaction_id')
        original_amount = context.get_dependency_field('validate_payment_eligibility', 'original_amount')

        # TAS-137: Use get_input_or() for task context with default
        refund_reason = context.get_input_or('refund_reason', 'customer_request')

        raise TaskerCore::Errors::PermanentError.new(
          'Upstream data not available for record update',
          error_code: 'MISSING_DEPENDENCIES'
        ) if eligibility.nil? || gateway_result.nil?

        payment_id ||= eligibility['payment_id']
        amount = (refund_amount_dep || gateway_result['refund_amount']).to_f
        currency = gateway_result['currency']
        gateway_transaction_id ||= gateway_result['gateway_transaction_id']

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

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            records_updated: true,
            payment_id: payment_id,
            refund_id: refund_id,
            record_id: record_id,
            payment_status: 'refunded',
            refund_status: 'completed',
            history_entries_created: records_updated.size,
            updated_at: Time.current.iso8601,
            namespace: 'payments',
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
          },
          metadata: {
            handler: self.class.name,
            record_update_id: record_update_id,
            record_id: record_id,
            records_updated: records_updated.size,
            all_successful: all_successful,
            net_impact: (amount - gateway_fee).round(2),
            payment_status: 'refunded',
            refund_status: 'completed'
          }
        )
      end
    end
  end
end
