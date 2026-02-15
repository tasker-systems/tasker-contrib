module Analytics
  class JobsController < ApplicationController
    def create
      job = AnalyticsJob.create!(
        source: job_params[:source],
        status: 'pending'
      )

      task = TaskerCore::Client.create_task(
        name:      'analytics_pipeline',
        namespace: 'data_pipeline_rb',
        context:   {
          source:           job_params[:source],
          date_range:       job_params[:date_range],
          filters:          job_params[:filters] || {},
          domain_record_id: job.id
        }
      )

      job.update!(task_uuid: task.task_uuid, status: 'running')

      render json: {
        id:        job.id,
        source:    job.source,
        status:    job.status,
        task_uuid: job.task_uuid,
        message:   'Analytics pipeline submitted'
      }, status: :created
    rescue StandardError => e
      Rails.logger.error("Analytics job creation failed: #{e.message}")
      render json: { error: "Pipeline submission failed: #{e.message}" }, status: :unprocessable_entity
    end

    def show
      job = AnalyticsJob.find(params[:id])
      render json: enrich_with_task_status(job)
    end

    private

    def job_params
      params.require(:job).permit(
        :source,
        date_range: [:start_date, :end_date],
        filters: [:region, :product_category, :min_revenue]
      )
    end
  end
end
