class JobSeekerProfile < ApplicationRecord
  belongs_to :user

  validates :user_id, presence: true
  validates :background_summary, presence: true, length: { maximum: 10_000 }
end
