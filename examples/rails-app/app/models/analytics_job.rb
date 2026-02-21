# frozen_string_literal: true

class AnalyticsJob < ApplicationRecord
  validates :source, presence: true, inclusion: {
    in: %w[production staging warehouse]
  }
  validates :status, presence: true, inclusion: {
    in: %w[pending running completed failed]
  }

  scope :by_source, ->(source) { where(source: source) }
  scope :recent, -> { order(created_at: :desc) }
end
