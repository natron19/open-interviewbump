class PasswordReset < ApplicationRecord
  belongs_to :user

  validates :token,      presence: true, uniqueness: true
  validates :expires_at, presence: true

  def expired?
    expires_at < Time.current
  end

  def used?
    used_at.present?
  end

  def valid_for_use?
    !expired? && !used?
  end
end
