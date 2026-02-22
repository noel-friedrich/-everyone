class HomeController < ApplicationController
  FALLBACK_MESSAGE = "KC needs someone to talk right now.".freeze
  skip_forgery_protection only: :initiate_call
  def index; end

  def initiate_call
    activation_id = SecureRandom.uuid
    intake = {
      feeling: params[:feeling].presence || "overwhelmed",
      trigger: params[:trigger].presence || "unspecified",
      urgency: params[:urgency].presence || "high"
    }
    user_id = params[:user_id].presence&.to_i || 1

    summary_payload = AgentServiceClient.new.start_activation(
      activation_id: activation_id,
      user_id: user_id,
      intake: intake
    )
    summary_text = summary_payload&.dig("summary_text").presence || FALLBACK_MESSAGE

    Rails.cache.write(
      activation_cache_key(activation_id),
      {
        "activation_id" => activation_id,
        "summary_text" => summary_text,
        "accepted_call_sid" => nil,
        "created_at" => Time.current.iso8601
      },
      expires_in: 30.days
    )

    webhook_base_url = ENV["PUBLIC_BASE_URL"].presence || request.base_url
    intro_url = build_webhook_url(webhook_base_url, twilio_voice_intro_path(activation_id: activation_id))
    status_url = build_webhook_url(webhook_base_url, twilio_voice_status_path(activation_id: activation_id))
    Rails.logger.info("twilio_webhook_urls base=#{webhook_base_url} intro=#{intro_url} status=#{status_url}")

    client = Twilio::REST::Client.new(
      ENV.fetch("TWILIO_ACCOUNT_SID"),
      ENV.fetch("TWILIO_AUTH_TOKEN")
    )

    call = client.calls.create(
      from: ENV.fetch("TWILIO_FROM_NUMBER"),
      to: ENV.fetch("TEST_NUMBER"),
      url: intro_url,
      status_callback: status_url,
      status_callback_method: "POST",
      status_callback_event: [ "initiated", "ringing", "answered", "completed" ]
    )

    Rails.logger.info("call_initiated activation_id=#{activation_id} call_sid=#{call.sid}")
    respond_to do |format|
      format.html { redirect_to root_path, notice: "Call initiated. SID: #{call.sid}" }
      format.json do
        render json: {
          status: "ok",
          activation_id: activation_id,
          call_sid: call.sid,
          summary_text: summary_text
        }, status: :ok
      end
    end
  rescue KeyError => e
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Missing environment variable: #{e.key}" }
      format.json { render json: { status: "error", error: "missing_env", key: e.key }, status: :unprocessable_entity }
    end
  rescue Twilio::REST::RestError => e
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Twilio error: #{e.message}" }
      format.json { render json: { status: "error", error: "twilio_error", message: e.message }, status: :bad_gateway }
    end
  end

  private

  def activation_cache_key(activation_id)
    "activation:#{activation_id}"
  end

  def build_webhook_url(base_url, path)
    "#{base_url.to_s.chomp('/')}#{path}"
  end
end
