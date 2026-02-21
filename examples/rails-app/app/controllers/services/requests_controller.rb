# frozen_string_literal: true

module Services
  class RequestsController < ApplicationController
    def create
      service_request = ServiceRequest.create!(
        user_id: request_params[:user_id],
        request_type: 'user_registration',
        status: 'pending'
      )

      task = TaskerCore::Client.create_task(
        name: 'user_registration',
        namespace: 'microservices_rb',
        context: {
          email: request_params[:email],
          name: request_params[:name],
          plan: request_params[:plan],
          referral_code: request_params[:referral_code],
          marketing_consent: request_params[:marketing_consent] || false,
          domain_record_id: service_request.id
        }
      )

      service_request.update!(task_uuid: task.task_uuid, status: 'in_progress')

      render json: {
        id: service_request.id,
        request_type: service_request.request_type,
        status: service_request.status,
        task_uuid: service_request.task_uuid,
        message: 'User registration workflow submitted'
      }, status: :created
    rescue StandardError => e
      Rails.logger.error("Service request creation failed: #{e.message}")
      render json: { error: "Registration submission failed: #{e.message}" }, status: :unprocessable_entity
    end

    def show
      service_request = ServiceRequest.find(params[:id])
      render json: enrich_with_task_status(service_request)
    end

    private

    def request_params
      params.require(:request).permit(
        :user_id, :email, :name, :plan, :referral_code, :marketing_consent
      )
    end
  end
end
