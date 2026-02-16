# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

# Polling helpers for verifying Tasker task completion via the orchestration API.
#
# Include this module in RSpec examples that need to wait for tasks to finish
# processing before asserting on step results.
#
# Usage:
#   include TaskPolling
#   task = wait_for_task_completion(task_uuid)
#   expect(task['status']).to eq('complete')
module TaskPolling
  ORCHESTRATION_URL = ENV.fetch('ORCHESTRATION_URL', 'http://localhost:8080')
  API_KEY = ENV.fetch('TASKER_API_KEY', 'test-api-key-full-access')
  DEFAULT_TIMEOUT = 30
  POLL_INTERVAL = 1

  # Truly terminal: no further progress possible regardless of retries.
  TERMINAL_STATUSES = %w[complete error cancelled].freeze

  # Also terminal but may appear before retries finish — treat as terminal
  # only after a grace period so the worker has time to process.
  FAILURE_STATUSES = %w[blocked_by_failures].freeze

  # Polls GET /v1/tasks/:uuid until the task reaches a terminal status.
  #
  # A task in "blocked_by_failures" is given a grace period before being
  # treated as terminal, since steps may still be in waiting_for_retry.
  #
  # @param task_uuid [String]
  # @param timeout [Integer] maximum seconds to wait (default 30)
  # @param poll_interval [Float] seconds between polls (default 1)
  # @return [Hash] the task response body
  # @raise [RuntimeError] if the task does not reach a terminal status within the timeout
  def wait_for_task_completion(task_uuid, timeout: DEFAULT_TIMEOUT, poll_interval: POLL_INTERVAL)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    failure_seen_at = nil

    loop do
      task = get_task(task_uuid)
      status = task['status']

      # Immediately terminal
      return task if TERMINAL_STATUSES.include?(status)

      # Failure status with grace period: keep polling for a few more seconds
      # in case retries are still in flight
      if FAILURE_STATUSES.include?(status)
        failure_seen_at ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
        elapsed_since_failure = Process.clock_gettime(Process::CLOCK_MONOTONIC) - failure_seen_at
        return task if elapsed_since_failure >= 10 # 10s grace period
      else
        failure_seen_at = nil # Reset if status changed back
      end

      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if remaining <= 0
        raise "Task #{task_uuid} did not complete within #{timeout}s. " \
              "Last status: #{status}, completion: #{task['completion_percentage']}%"
      end

      sleep [poll_interval, remaining].min
    end
  end

  # Fetches a single task from the orchestration API.
  #
  # @param task_uuid [String]
  # @return [Hash] parsed JSON response
  def get_task(task_uuid)
    uri = URI("#{ORCHESTRATION_URL}/v1/tasks/#{task_uuid}")
    req = Net::HTTP::Get.new(uri)
    req['X-API-Key'] = API_KEY

    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end

    raise "GET #{uri} returned #{response.code}: #{response.body}" unless response.code == '200'

    JSON.parse(response.body)
  end

  # Returns the steps array from a task response.
  #
  # @param task_uuid [String]
  # @return [Array<Hash>]
  def get_task_steps(task_uuid)
    task = get_task(task_uuid)
    task['steps'] || []
  end

  # Finds a specific step by name within a task.
  #
  # @param task_uuid [String]
  # @param step_name [String]
  # @return [Hash, nil]
  def find_step(task_uuid, step_name)
    get_task_steps(task_uuid).find { |s| s['name'] == step_name }
  end
end
