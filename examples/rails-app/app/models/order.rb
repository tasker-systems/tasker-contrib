class Order < ApplicationRecord
  validates :customer_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :items, presence: true
  validates :status, presence: true, inclusion: {
    in: %w[pending processing completed failed cancelled]
  }
  validates :total, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :by_status, ->(status) { where(status: status) }
  scope :recent, -> { order(created_at: :desc) }
end
