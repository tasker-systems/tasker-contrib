class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
  rescue_from ActionController::ParameterMissing, with: :bad_request

  private

  def not_found(exception)
    render json: { error: exception.message }, status: :not_found
  end

  def unprocessable_entity(exception)
    render json: { error: exception.record.errors.full_messages }, status: :unprocessable_entity
  end

  def bad_request(exception)
    render json: { error: exception.message }, status: :bad_request
  end

  # Fetch task status from Tasker orchestration and merge with domain record
  def enrich_with_task_status(record)
    base = record.as_json
    return base unless record.task_uuid.present?

    begin
      task = TaskerCore::Client.get_task(record.task_uuid)
      base.merge(
        'task_status' => task['state'],
        'task_steps'  => task['steps']&.map { |s| { name: s['name'], state: s['state'] } }
      )
    rescue StandardError => e
      Rails.logger.warn("Failed to fetch task status for #{record.task_uuid}: #{e.message}")
      base.merge('task_status' => 'unknown', 'task_error' => e.message)
    end
  end
end
