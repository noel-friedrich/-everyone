require "json"
require "net/http"
require "uri"

class HomeController < ApplicationController
  FALLBACK_MESSAGE = "KC needs someone to talk right now.".freeze
  DEV_PUBLIC_BASE_URL = "https://britany-schizogenetic-luz.ngrok-free.dev".freeze
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

    webhook_base_url = resolved_public_base_url
    intro_url = build_webhook_url(webhook_base_url, twilio_voice_intro_path(activation_id: activation_id))
    status_url = build_webhook_url(webhook_base_url, twilio_voice_status_path(activation_id: activation_id))

    if local_base_url?(webhook_base_url)
      return respond_to do |format|
        format.html { redirect_to root_path, alert: "PUBLIC_BASE_URL is not set to a public URL. Start ngrok and set PUBLIC_BASE_URL." }
        format.json do
          render json: {
            status: "error",
            error: "invalid_public_base_url",
            message: "Twilio needs a public webhook URL. Set PUBLIC_BASE_URL to your ngrok https URL.",
            debug: {
              webhook_base_url: webhook_base_url,
              intro_url: intro_url,
              status_url: status_url
            }
          }, status: :unprocessable_entity
        end
      end
    end
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
      format.json do
        render json: {
          status: "error",
          error: "twilio_error",
          message: e.message,
          debug: {
            webhook_base_url: webhook_base_url,
            intro_url: intro_url,
            status_url: status_url
          }
        }, status: :bad_gateway
      end
    end
  end

  private

  def activation_cache_key(activation_id)
    "activation:#{activation_id}"
  end

  def build_webhook_url(base_url, path)
    "#{base_url.to_s.chomp('/')}#{path}"
  end

  def resolved_public_base_url
    ENV["PUBLIC_BASE_URL"].presence || ngrok_public_url.presence || development_public_base_url || request.base_url
  end

  def ngrok_public_url
    uri = URI.parse("http://127.0.0.1:4040/api/tunnels")
    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    tunnels = Array(data["tunnels"])
    https_tunnel = tunnels.find { |t| t["public_url"].to_s.start_with?("https://") }
    https_tunnel&.dig("public_url")
  rescue StandardError => e
    Rails.logger.warn("ngrok_url_lookup_failed #{e.class}: #{e.message}")
    nil
  end

  def local_base_url?(url)
    host = URI.parse(url).host
    host.blank? || [ "localhost", "127.0.0.1", "::1" ].include?(host)
  rescue URI::InvalidURIError
    true
  end

  def development_public_base_url
    return nil unless Rails.env.development?

    DEV_PUBLIC_BASE_URL
  end
end
