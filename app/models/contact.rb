class Contact < ApplicationRecord
  E164_REGEX = /\A\+[1-9]\d{1,14}\z/

  belongs_to :user

  enum :consent_status, {
    pending: 0,
    confirmed: 1,
    revoked: 2
  }
  enum :priority, {
    low: 0,
    moderate: 1,
    high: 2
  }, prefix: true

  before_validation :normalize_phone_e164

  validates :name, presence: true
  validates :phone_e164, presence: true, format: { with: E164_REGEX }
  validates :priority, inclusion: { in: priorities.keys }
  validates :response_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :miss_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :avg_answer_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :phone_e164, uniqueness: { scope: :user_id }
  validate :preferred_hours_pair

  private

  def normalize_phone_e164
    self.phone_e164 = phone_e164.to_s.strip.presence
  end

  def preferred_hours_pair
    if preferred_hours_start.present? ^ preferred_hours_end.present?
      errors.add(:base, "preferred_hours_start and preferred_hours_end must both be set")
    end
  end
end
