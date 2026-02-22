class ConsentsController < ApplicationController
  VALID_RESPONSE_STATUSES = %w[confirmed declined].freeze

  def show
    @consent_hash = normalize_hash(params[:hash])
    @consent = @consent_hash ? HelperConsent.find_by(consent_hash: @consent_hash) : nil
    @status = @consent&.status || "pending"
  end

  def respond
    consent_hash = normalize_hash(params[:hash])
    status = params[:status].to_s

    unless consent_hash
      return redirect_to consent_path, alert: "Invalid confirmation link."
    end

    unless VALID_RESPONSE_STATUSES.include?(status)
      return redirect_to consent_path(hash: consent_hash), alert: "Invalid response."
    end

    consent = HelperConsent.find_or_initialize_by(consent_hash: consent_hash)
    consent.status = status
    consent.save!

    redirect_to consent_path(hash: consent_hash), notice: "Your response was recorded."
  rescue ActiveRecord::RecordInvalid
    redirect_to consent_path(hash: consent_hash), alert: "Could not save your response."
  end

  private

  def normalize_hash(value)
    candidate = value.to_s.strip.downcase
    candidate.match?(/\A\h{64}\z/) ? candidate : nil
  end
end
