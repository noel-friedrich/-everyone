class CallSession < ApplicationRecord
  STATUSES = %w[calling connected completed].freeze

  has_many :call_session_contacts, dependent: :destroy

  validates :room_name, presence: true
  validates :caller_name, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  def refresh_status!
    next_status =
      if call_session_contacts.where(status: "joined").exists?
        "connected"
      elsif call_session_contacts.exists? && call_session_contacts.where.not(status: CallSessionContact::FINAL_STATUSES).none?
        "completed"
      else
        "calling"
      end

    update!(status: next_status) if status != next_status
  end
end
