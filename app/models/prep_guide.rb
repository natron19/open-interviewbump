class PrepGuide < ApplicationRecord
  belongs_to :prep_session

  validates :prep_session_id, presence: true
end
