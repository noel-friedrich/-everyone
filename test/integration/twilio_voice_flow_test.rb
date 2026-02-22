require "test_helper"

class TwilioVoiceFlowTest < ActionDispatch::IntegrationTest
  setup do
    @previous_token = ENV["TWILIO_AUTH_TOKEN"]
    @previous_cache = Rails.cache
    ENV["TWILIO_AUTH_TOKEN"] = "test_auth_token"
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.clear
  end

  teardown do
    ENV["TWILIO_AUTH_TOKEN"] = @previous_token
    Rails.cache = @previous_cache
  end

  test "intro twiml includes summary and gather prompt" do
    activation_id = "act_intro_1"
    Rails.cache.write(cache_key(activation_id), { "summary_text" => "Alex is feeling overwhelmed and needs support now." })

    path = twilio_voice_intro_path(activation_id: activation_id)
    headers = twilio_headers(full_url(path), {})
    post path, headers: headers

    assert_response :success
    assert_includes response.body, "Alex is feeling overwhelmed and needs support now."
    assert_includes response.body, "<Gather"
    assert_includes response.body, "Press 1 to connect now."
  end

  test "intro returns safe hangup for unknown activation" do
    path = twilio_voice_intro_path(activation_id: "missing")
    headers = twilio_headers(full_url(path), {})
    post path, headers: headers

    assert_response :success
    assert_includes response.body, "This request is no longer available. Goodbye."
  end

  test "accept endpoint is first-responder-wins and idempotent" do
    activation_id = "act_accept_1"
    Rails.cache.write(cache_key(activation_id), { "summary_text" => "summary", "accepted_call_sid" => nil })

    accept_path = twilio_voice_accept_path(activation_id: activation_id)

    first_params = { "Digits" => "1", "CallSid" => "CA_FIRST" }
    post accept_path, params: first_params, headers: twilio_headers(full_url(accept_path), first_params)
    assert_response :success
    assert_includes response.body, "confirmed responder"
    assert_equal "CA_FIRST", Rails.cache.read(cache_key(activation_id))["accepted_call_sid"]

    second_params = { "Digits" => "1", "CallSid" => "CA_SECOND" }
    post accept_path, params: second_params, headers: twilio_headers(full_url(accept_path), second_params)
    assert_response :success
    assert_includes response.body, "already accepted"
    assert_equal "CA_FIRST", Rails.cache.read(cache_key(activation_id))["accepted_call_sid"]
  end

  test "webhook rejects missing signature" do
    post twilio_voice_intro_path(activation_id: "act_no_sig")
    assert_response :unauthorized
  end

  private

  def cache_key(activation_id)
    "activation:#{activation_id}"
  end

  def full_url(path)
    "http://www.example.com#{path}"
  end

  def twilio_headers(url, params)
    validator = Twilio::Security::RequestValidator.new(ENV.fetch("TWILIO_AUTH_TOKEN"))
    signature = validator.build_signature_for(url, params)
    { "X-Twilio-Signature" => signature }
  end
end
