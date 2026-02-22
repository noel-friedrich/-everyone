module Api
  class HelperConsentsController < ActionController::API
    MAX_HASHES_PER_REQUEST = 500

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
  end
end
