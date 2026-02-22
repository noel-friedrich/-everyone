class HelperConsent < ApplicationRecord
  STATUSES = %w[pending confirmed declined].freeze

  validates :consent_hash,
            presence: true,
            uniqueness: true,
            format: { with: /\A\h{64}\z/, message: "must be a SHA-256 hex digest" }
  validates :status, presence: true, inclusion: { in: STATUSES }
end
