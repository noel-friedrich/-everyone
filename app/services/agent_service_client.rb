require "json"
require "net/http"
require "uri"

class AgentServiceClient
  DEFAULT_URL = "http://localhost:8001".freeze

  def initialize(base_url: ENV.fetch("AGENT_SERVICE_URL", DEFAULT_URL), timeout_seconds: 5)
    @base_url = base_url
    @timeout_seconds = timeout_seconds
  end

  def start_activation(activation_id:, user_id:, intake:, escalation_level: "low", contacts: [])
    uri = URI.parse("#{@base_url}/v1/activations/start")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = {
      activation_id: activation_id,
      user_id: user_id,
      escalation_level: escalation_level,
      intake: intake,
      contacts: contacts
    }.to_json

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      read_timeout: @timeout_seconds,
      open_timeout: @timeout_seconds
    ) { |http| http.request(request) }

    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError, SocketError, Timeout::Error, Errno::ECONNREFUSED, Net::ReadTimeout, Net::OpenTimeout => e
    Rails.logger.warn("AgentServiceClient request failed: #{e.class}: #{e.message}")
    nil
  end
end
