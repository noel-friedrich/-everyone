module Api
  class HelperConsentsController < ActionController::API
    MAX_HASHES_PER_REQUEST = 500
    E164_REGEX = /\A\+[1-9]\d{1,14}\z/

    # POST /api/helper_consents/bulk_lookup
    # Params:
    #   hashes[] - array of SHA-256 hex digests
    # Returns:
    #   { consents: { "<hash>": "<status>" } }
    def bulk_lookup
      hashes = normalized_hashes(params.require(:hashes))

      if hashes.empty?
        return render json: { error: "hashes must be a non-empty array" }, status: :unprocessable_entity
      end

      if hashes.length > MAX_HASHES_PER_REQUEST
        return render json: { error: "hashes exceeds #{MAX_HASHES_PER_REQUEST} items" }, status: :unprocessable_entity
      end

      consents = HelperConsent.where(consent_hash: hashes).pluck(:consent_hash, :status).to_h
      render json: { consents: consents }, status: :ok
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/helper_consents
    # Params:
    #   hash   - SHA-256 hex digest for "#{CLIENT_UID}#{HELPER_NUMBER}"
    #   status - pending|confirmed|declined
    def upsert
      consent_hash = normalize_hash(params.require(:hash))
      status = params.require(:status).to_s

      unless consent_hash
        return render json: { error: "hash must be a SHA-256 hex digest" }, status: :unprocessable_entity
      end

      unless HelperConsent::STATUSES.include?(status)
        return render json: { error: "status must be one of: #{HelperConsent::STATUSES.join(', ')}" },
                      status: :unprocessable_entity
      end

      consent = HelperConsent.find_or_initialize_by(consent_hash: consent_hash)
      consent.status = status
      consent.save!

      render json: { hash: consent.consent_hash, status: consent.status }, status: :ok
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end

    # POST /api/helper_consents/send_opt_in
    # Params:
    #   hash   - SHA-256 hex digest for "#{CLIENT_UID}#{HELPER_NUMBER}"
    #   number - helper phone number in E.164 format
    #   name   - optional helper display name
    def send_opt_in
      consent_hash = normalize_hash(params.require(:hash))
      number = normalize_number(params.require(:number))
      name = params[:name].to_s.strip.presence || "there"

      unless consent_hash
        return render json: { error: "hash must be a SHA-256 hex digest" }, status: :unprocessable_entity
      end

      unless number
        return render json: { error: "number must be E.164 format, e.g. +491701234567" },
                      status: :unprocessable_entity
      end

      existing = HelperConsent.find_by(consent_hash: consent_hash)
      if existing&.status == "declined"
        return render json: { error: "This helper has declined and cannot be requested again." }, status: :conflict
      end

      consent = existing || HelperConsent.new(consent_hash: consent_hash)

      consent_link = "#{request.base_url}/consent?hash=#{consent_hash}"
      message = "Hi #{name}, confirm if you want to receive alerts: #{consent_link}"

      result = ::TwilioService.new.send_sms(to: number, message: message)
      consent.status = "pending"
      consent.save!

      render json: {
        hash: consent_hash,
        status: consent.status,
        sms_sid: result.sid,
        to: result.to
      }, status: :ok
    rescue KeyError => e
      render json: { error: "Missing environment variable: #{e.key}" }, status: :internal_server_error
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    rescue Twilio::REST::RestError => e
      render json: { error: "Twilio error: #{e.message}" }, status: :unprocessable_entity
    end

    private

    def normalized_hashes(raw_hashes)
      return [] unless raw_hashes.is_a?(Array)

      raw_hashes
        .map { |value| normalize_hash(value) }
        .compact
        .uniq
    end

    def normalize_hash(value)
      candidate = value.to_s.strip.downcase
      candidate.match?(/\A\h{64}\z/) ? candidate : nil
    end

    def normalize_number(value)
      candidate = value.to_s.strip.gsub(/[^\d+]/, "")
      return nil if candidate.blank?

      candidate = "+#{candidate}" unless candidate.start_with?("+")
      candidate.match?(E164_REGEX) ? candidate : nil
    end
  end
end
