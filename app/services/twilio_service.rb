class TwilioService
  attr_reader :client

  def initialize
    @client = Twilio::REST::Client.new(
      ENV.fetch("TWILIO_ACCOUNT_SID"),
      ENV.fetch("TWILIO_AUTH_TOKEN")
    )
  end

  def from_number
    ENV.fetch("TWILIO_FROM_NUMBER")
  end

  # -------------------------------------------------------------------
  # Generate a Twilio Access Token for browser-based voice (WebRTC)
  # -------------------------------------------------------------------
  def generate_access_token(identity:)
    account_sid = ENV.fetch("TWILIO_ACCOUNT_SID")
    api_key     = ENV.fetch("TWILIO_API_KEY")
    api_secret  = ENV.fetch("TWILIO_API_SECRET")
    app_sid     = ENV.fetch("TWILIO_TWIML_APP_SID")

    grant = Twilio::JWT::AccessToken::VoiceGrant.new
    grant.outgoing_application_sid = app_sid
    grant.incoming_allow = true

    token = Twilio::JWT::AccessToken.new(
      account_sid,
      api_key,
      api_secret,
      [grant],
      identity: identity,
      ttl: 3600
    )

    token.to_jwt
  end

  # -------------------------------------------------------------------
  # Call everyone simultaneously using inline TwiML + conference
  # -------------------------------------------------------------------
  # Returns an array of results per number:
  #   [{ number: "+1...", call_sid: "CA...", status: "calling" }, ...]
  # -------------------------------------------------------------------
  def call_everyone(numbers:, room_name:, caller_name: "Someone")
    twiml_bin_url = ENV.fetch("TWILIO_TWIML_BIN_URL")
    gather_action_url = "#{twiml_bin_url}?RoomName=#{CGI.escape(room_name)}"

    contact_twiml = Twilio::TwiML::VoiceResponse.new do |r|
      r.say(
        voice: "alice",
        message: "Hey. #{caller_name} triggered at everyone. They need to talk to someone right now."
      )
      r.gather(
        num_digits: 1,
        action: gather_action_url,
        method: "POST",
        timeout: 15
      ) do |g|
        g.say(
          voice: "alice",
          message: "Press 1 to connect with them. Or just hang up if you can't right now."
        )
      end
      r.say(
        voice: "alice",
        message: "We didn't get a response. Thanks for being available. Goodbye."
      )
      r.hangup
    end.to_s

    results = []

    numbers.each do |number|
      normalized = normalize_number(number)
      next if normalized.blank?

      begin
        call = client.calls.create(
          from: from_number,
          to: normalized,
          twiml: contact_twiml
        )

        results << { number: normalized, call_sid: call.sid, status: "calling" }
      rescue Twilio::REST::RestError => e
        Rails.logger.error("[TwilioService] Failed to call #{normalized}: #{e.message}")
        results << { number: normalized, call_sid: nil, status: "failed", error: e.message }
      end
    end

    results
  end

  # -------------------------------------------------------------------
  # Hang up a list of calls by their SIDs
  # -------------------------------------------------------------------
  # call_sids – array of Twilio Call SIDs to terminate
  # -------------------------------------------------------------------
  def hangup_calls(call_sids:)
    results = []

    call_sids.each do |sid|
      next if sid.blank?

      begin
        client.calls(sid).update(status: "completed")
        results << { call_sid: sid, status: "hung_up" }
      rescue Twilio::REST::RestError => e
        Rails.logger.warn("[TwilioService] Could not hang up #{sid}: #{e.message}")
        results << { call_sid: sid, status: "failed", error: e.message }
      end
    end

    results
  end

  # -------------------------------------------------------------------
  # Send SMS to one number
  # -------------------------------------------------------------------
  def send_sms(to:, message:)
    client.messages.create(
      from: from_number,
      to: normalize_number(to),
      body: message
    )
  end

  # -------------------------------------------------------------------
  # Send SMS to many numbers
  # -------------------------------------------------------------------
  def send_sms_all(numbers:, message:)
    results = []

    numbers.each do |number|
      normalized = normalize_number(number)
      next if normalized.blank?

      begin
        msg = client.messages.create(
          from: from_number,
          to: normalized,
          body: message
        )
        results << { number: normalized, sid: msg.sid, status: "sent" }
      rescue Twilio::REST::RestError => e
        Rails.logger.error("[TwilioService] SMS to #{normalized} failed: #{e.message}")
        results << { number: normalized, sid: nil, status: "failed", error: e.message }
      end
    end

    results
  end

  private

  def normalize_number(number)
    cleaned = number.to_s.strip.gsub(/[^\d+]/, "")
    cleaned.start_with?("+") ? cleaned : "+#{cleaned}"
  rescue
    nil
  end
end
