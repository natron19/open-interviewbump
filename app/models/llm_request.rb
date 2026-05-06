class LlmRequest < ApplicationRecord
  belongs_to :user
  belongs_to :ai_template, optional: true

  STATUSES = %w[pending success error timeout gatekeeper_blocked budget_exceeded].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :today,      -> { where(created_at: Date.current.all_day) }
  scope :this_week,  -> { where(created_at: 1.week.ago..Time.current) }
  scope :successful, -> { where(status: "success") }
  scope :failed,     -> { where(status: %w[error timeout gatekeeper_blocked budget_exceeded]) }
  scope :recent,     -> { order(created_at: :desc).limit(100) }
end
