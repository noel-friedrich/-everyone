class CallSessionContact < ApplicationRecord
  STATUSES = %w[
    queued
    calling
    ringing
    picked_up
    joined
    declined
    no_answer
    busy
    failed
    canceled
    completed
  ].freeze
  FINAL_STATUSES = %w[joined declined no_answer busy failed canceled completed].freeze
  E164_REGEX = /\A\+[1-9]\d{1,14}\z/

  belongs_to :call_session

  validates :phone_number, presence: true, format: { with: E164_REGEX }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :call_sid, uniqueness: true, allow_nil: true
  validates :phone_number, uniqueness: { scope: :call_session_id }
end
