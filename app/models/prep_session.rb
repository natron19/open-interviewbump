class PrepSession < ApplicationRecord
  belongs_to :user
  has_one :prep_guide, dependent: :destroy

  STATUSES = %w[pending researching complete failed].freeze

  validates :user_id,         presence: true
  validates :job_title,       presence: true
  validates :company,         presence: true
  validates :status,          inclusion: { in: STATUSES }
  validates :job_description, length: { maximum: 10_000 }, allow_blank: true
end
