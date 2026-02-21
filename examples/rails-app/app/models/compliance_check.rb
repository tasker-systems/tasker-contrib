# frozen_string_literal: true

class ComplianceCheck < ApplicationRecord
  validates :order_ref, presence: true
  validates :namespace, presence: true, inclusion: {
    in: %w[customer_success_rb payments_rb]
  }
  validates :status, presence: true, inclusion: {
    in: %w[pending in_progress approved denied completed failed]
  }

  scope :by_namespace, ->(ns) { where(namespace: ns) }
  scope :recent, -> { order(created_at: :desc) }
end
