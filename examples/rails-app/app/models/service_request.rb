# frozen_string_literal: true

class ServiceRequest < ApplicationRecord
  validates :request_type, presence: true, inclusion: {
    in: %w[user_registration account_update plan_change]
  }
  validates :status, presence: true, inclusion: {
    in: %w[pending in_progress completed failed]
  }

  scope :by_type, ->(type) { where(request_type: type) }
  scope :recent, -> { order(created_at: :desc) }
end
