# Home Assistant service for interacting with Home Assistant API
# Provides simple methods to get/set entities and make service calls

require "net/http"
require "json"

class HomeAssistantService
  class Error < StandardError; end
  class ConnectionError < Error; end
  class AuthenticationError < Error; end

  class NotFoundError < Error; end

  attr_reader :base_url, :token, :timeout

  def initialize
    @base_url = Rails.configuration.home_assistant_url
    @token = Rails.configuration.home_assistant_token
    @timeout = Rails.configuration.home_assistant_timeout

    raise Error, "Home Assistant URL not configured" unless @base_url
    raise Error, "Home Assistant token not configured" unless @token
  end

  # Get all entities
  def entities
    get("/api/states")
  end

  # Get entity by entity_id
  def entity(entity_id)
    get("/api/states/#{entity_id}")
  rescue NotFoundError
    nil
  end

  # Get entities by domain (e.g., 'light', 'switch', 'sensor')
  def entities_by_domain(domain)
    entities.select { |entity| entity["entity_id"].start_with?("#{domain}.") }
  end

  # Get entity state
  def entity_state(entity_id)
    entity_data = entity(entity_id)
    entity_data&.dig("state")
  end

  # Set entity state (for writable entities)
  def set_entity_state(entity_id, state, attributes = {})
    data = {
      state: state,
      attributes: attributes
    }
    post("/api/states/#{entity_id}", data)
  end

  # Call a service
  def call_service(domain, service, data = {})
    post("/api/services/#{domain}/#{service}", data)
  end

  # Turn on entity (works for lights, switches, etc.)
  def turn_on(entity_id, **options)
    data = { entity_id: entity_id }.merge(options)
    call_service(entity_domain(entity_id), "turn_on", data)
  end

  # Turn off entity
  def turn_off(entity_id, **options)
    data = { entity_id: entity_id }.merge(options)
    call_service(entity_domain(entity_id), "turn_off", data)
  end

  # Toggle entity
  def toggle(entity_id, **options)
    data = { entity_id: entity_id }.merge(options)
    call_service(entity_domain(entity_id), "toggle", data)
  end

  # Get all services
  def services
    get("/api/services")
  end

  # Get services for a specific domain
  def domain_services(domain)
    services_data = services
    return nil unless services_data.is_a?(Array)

    domain_service = services_data.find { |service| service["domain"] == domain }
    domain_service&.dig("services")
  end

  # Check if Home Assistant is available
  def available?
    get("/api/")
    true
  rescue StandardError
    false
  end

  # Get Home Assistant configuration
  def config
    get("/api/config")
  end

  # Get events
  def events
    get("/api/events")
  end

  # Fire an event
  def fire_event(event_type, data = {})
    post("/api/events/#{event_type}", data)
  end

  # Call conversation agent
  def conversation_process(text:, agent_id: nil, conversation_id: nil)
    data = { text: text }
    data[:agent_id] = agent_id if agent_id
    data[:conversation_id] = conversation_id if conversation_id

    post("/api/conversation/process", data)
  end

  # Send conversation response for performance mode
  def send_conversation_response(response_data)
    # Extract speech text from response data structure
    speech_text = response_data.dig(:response, :speech, :plain, :speech) ||
                  response_data.dig("response", "speech", "plain", "speech")

    return { error: "No speech text found in response data" } unless speech_text

    # Use existing conversation process method
    conversation_process(
      text: speech_text,
      conversation_id: response_data[:conversation_id] || response_data["conversation_id"]
    )
  end

  # Get history for entity
  def history(entity_id, start_time = nil, end_time = nil)
    path = "/api/history/period"
    path += "/#{start_time.iso8601}" if start_time
    params = {}
    params[:end_time] = end_time.iso8601 if end_time
    params[:filter_entity_id] = entity_id

    query_string = params.any? ? "?#{URI.encode_www_form(params)}" : ""
    get("#{path}#{query_string}")
  end

  private

  def entity_domain(entity_id)
    entity_id.split(".").first
  end

  def get(path)
    request = build_request(Net::HTTP::Get, path)
    make_request(request)
  end

  def post(path, data = {})
    request = build_request(Net::HTTP::Post, path)
    request.body = data.to_json
    make_request(request)
  end

  def build_request(klass, path)
    uri = URI("#{base_url}#{path}")
    request = klass.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request
  end

  def make_request(request)
    uri = URI(request.uri)

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: timeout) do |http|
      response = http.request(request)

      case response.code.to_i
      when 200..299
        response.body.empty? ? {} : JSON.parse(response.body)
      when 401, 403
        raise AuthenticationError, "Authentication failed: #{response.body}"
      when 404
        raise NotFoundError, "Resource not found: #{response.body}"
      else
        raise Error, "HTTP #{response.code}: #{response.body}"
      end
    end
  rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
    raise ConnectionError, "Connection timeout to Home Assistant"
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
    raise ConnectionError, "Cannot connect to Home Assistant at #{base_url}"
  rescue JSON::ParserError => e
    raise Error, "Invalid JSON response: #{e.message}"
  end

  # Class methods for global access
  class << self
    def instance
      @instance ||= new
    end

    def method_missing(method_name, *args, &block)
      if instance.respond_to?(method_name)
        instance.send(method_name, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      instance.respond_to?(method_name, include_private) || super
    end
  end
end
