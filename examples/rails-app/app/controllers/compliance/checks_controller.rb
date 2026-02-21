# frozen_string_literal: true

module Compliance
  class ChecksController < ApplicationController
    def create
      check = ComplianceCheck.create!(
        order_ref: check_params[:order_ref],
        namespace: check_params[:namespace],
        status: 'pending'
      )

      # Route to the correct template based on namespace
      template_name = case check_params[:namespace]
                      when 'customer_success_rb', 'payments_rb' then 'process_refund'
                      else
                        raise ArgumentError, "Unknown namespace: #{check_params[:namespace]}"
                      end

      task = TaskerCore::Client.create_task(
        name: template_name,
        namespace: check_params[:namespace],
        context: check_params.to_h.merge(domain_record_id: check.id)
      )

      check.update!(task_uuid: task.task_uuid, status: 'in_progress')

      render json: {
        id: check.id,
        namespace: check.namespace,
        order_ref: check.order_ref,
        status: check.status,
        task_uuid: check.task_uuid,
        message: "#{check.namespace} refund workflow submitted"
      }, status: :created
    rescue StandardError => e
      Rails.logger.error("Compliance check creation failed: #{e.message}")
      render json: { error: "Compliance check failed: #{e.message}" }, status: :unprocessable_entity
    end

    def show
      check = ComplianceCheck.find(params[:id])
      render json: enrich_with_task_status(check)
    end

    private

    def check_params
      params.require(:check).permit(
        :namespace, :order_ref, :ticket_id, :customer_id,
        :refund_amount, :reason, :agent_id, :priority,
        :payment_id, :currency, :original_transaction_id, :idempotency_key,
        metadata: {}
      )
    end
  end
end
