class TwilioVoiceController < ApplicationController
  skip_forgery_protection
  before_action :validate_twilio_request!

  FALLBACK_MESSAGE = "KC needs someone to talk right now.".freeze

  def intro
    activation_id = params[:activation_id].to_s
    activation = read_activation(activation_id)

    return render_twiml(invalid_activation_response) if activation.blank?

    call_sid = params[:CallSid].to_s
    Rails.logger.info("twilio_intro activation_id=#{activation_id} call_sid=#{call_sid}")

    response = Twilio::TwiML::VoiceResponse.new
    response.say(message: activation.fetch("summary_text", FALLBACK_MESSAGE), voice: "alice")
    response.gather(
      input: "dtmf",
      num_digits: 1,
      action: twilio_voice_accept_url(activation_id: activation_id),
      method: "POST",
      timeout: 7
    ) do |gather|
      gather.say(message: "Press 1 to connect now.", voice: "alice")
    end
    response.say(message: "No input received. Goodbye.", voice: "alice")
    response.hangup

    render_twiml(response)
  end

  def accept
    activation_id = params[:activation_id].to_s
    activation = read_activation(activation_id)
    return render_twiml(invalid_activation_response) if activation.blank?

    call_sid = params[:CallSid].to_s
    digits = params[:Digits].to_s
    accepted_call_sid = activation["accepted_call_sid"].to_s

    response = Twilio::TwiML::VoiceResponse.new

    if digits != "1"
      response.say(message: "We did not receive a valid confirmation. Goodbye.", voice: "alice")
      response.hangup
      return render_twiml(response)
    end

    if accepted_call_sid.present? && accepted_call_sid != call_sid
      response.say(message: "Someone has already accepted this request. Thank you.", voice: "alice")
      response.hangup
      return render_twiml(response)
    end

    if accepted_call_sid.blank?
      activation["accepted_call_sid"] = call_sid
      activation["accepted_at"] = Time.current.iso8601
      write_activation(activation_id, activation)
      Rails.logger.info("twilio_accept activation_id=#{activation_id} accepted_call_sid=#{call_sid}")
    end

    response.say(message: "Thank you. You are now the confirmed responder.", voice: "alice")
    response.hangup
    render_twiml(response)
  end

  def status
    activation_id = params[:activation_id].to_s
    call_sid = params[:CallSid].to_s
    call_status = params[:CallStatus].to_s
    Rails.logger.info("twilio_status activation_id=#{activation_id} call_sid=#{call_sid} status=#{call_status}")
    head :ok
  end

  private

  def render_twiml(response)
    render xml: response.to_s, content_type: "text/xml"
  end

  def invalid_activation_response
    response = Twilio::TwiML::VoiceResponse.new
    response.say(message: "This request is no longer available. Goodbye.", voice: "alice")
    response.hangup
    response
  end

  def read_activation(activation_id)
    Rails.cache.read(activation_cache_key(activation_id))
  end

  def write_activation(activation_id, payload)
    Rails.cache.write(activation_cache_key(activation_id), payload, expires_in: 30.days)
  end

  def activation_cache_key(activation_id)
    "activation:#{activation_id}"
  end

  def validate_twilio_request!
    if Rails.env.development? && ENV.fetch("TWILIO_SKIP_SIGNATURE_VALIDATION", "true") == "true"
      Rails.logger.warn("twilio_signature_validation_skipped_in_development")
      return
    end

    signature = request.headers["X-Twilio-Signature"].to_s
    token = ENV["TWILIO_AUTH_TOKEN"].to_s
    return head :unauthorized if signature.blank? || token.blank?

    validator = Twilio::Security::RequestValidator.new(token)
    params_hash = request.request_parameters.to_h
    candidate_urls = [
      request.original_url.to_s,
      request.original_url.to_s.sub(/\Ahttp:/, "https:"),
      request.original_url.to_s.sub(/\Ahttps:/, "http:")
    ].uniq

    valid = candidate_urls.any? { |url| validator.validate(url, params_hash, signature) }
    unless valid
      Rails.logger.warn("twilio_signature_validation_failed url=#{request.original_url} params=#{params_hash.keys.sort.join(',')}")
      head :unauthorized
    end
  end
end
