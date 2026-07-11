# frozen_string_literal: true

# In-memory stand-in for HomeAssistantService, used by the scenario harness and
# the /admin simulator to exercise the cube's full brain → translator → device
# pipeline WITHOUT a real Home Assistant or any hardware.
#
# Inject it via the singleton seam:
#
#   HomeAssistantService.instance = FakeHomeAssistant.new(persona: "jax",
#     entities: { "light.cube_inner" => { "state" => "on" } })
#   ... drive a conversation / proactive trigger ...
#   HomeAssistantService.reset_instance!   # restore the real backend
#
# Because HomeAssistantService's class methods delegate to `.instance`, every
# call site that goes through the class (or `.instance`) now talks to the fake.
# Direct `HomeAssistantService.new` callers bypass it — those are being migrated
# to `.instance` so the fake is authoritative everywhere.
#
# It records every service call, conversation request, and fired event so
# scenario specs can assert on what the cube *did* to its environment
# ("did it turn the lights orange?") rather than on internal mocks.
class FakeHomeAssistant
  attr_reader :service_calls, :conversation_requests, :fired_events

  # entities: { "light.cube_inner" => { "state" => "on", "attributes" => {...} } }
  # persona:  seeds input_select.current_persona (how CubePersona resolves persona)
  # conversation_response: canned reply returned by #conversation_process
  def initialize(entities: {}, persona: "buddy", conversation_response: nil)
    @entities = {}
    @service_calls = []
    @conversation_requests = []
    @fired_events = []
    @conversation_response = conversation_response

    entities.each do |id, data|
      data = stringify(data)
      set_state(id, data["state"] || "on", data["attributes"] || {})
    end
    self.persona = persona if persona
  end

  # ---- scenario scripting helpers ----

  # last_updated mirrors the real HASS state object (always present, ISO8601);
  # pass it explicitly to script freshness-sensitive scenarios (camera throttle).
  def set_state(entity_id, state, attributes = {}, last_updated: Time.current.utc.iso8601)
    @entities[entity_id] = {
      "entity_id" => entity_id,
      "state" => state.to_s,
      "attributes" => stringify(attributes),
      "last_updated" => last_updated
    }
  end

  def persona=(name)
    set_state("input_select.current_persona", name)
  end

  def conversation_response=(response)
    @conversation_response = response
  end

  # Service calls aimed at a given HA domain (e.g. "light", "media_player").
  def service_calls_for(domain)
    @service_calls.select { |c| c[:domain] == domain.to_s }
  end

  # ---- HomeAssistantService public interface (drop-in) ----

  def entities
    @entities.values.map(&:dup)
  end

  def entity(entity_id)
    @entities[entity_id]&.dup
  end

  def entities_by_domain(domain)
    entities.select { |e| e["entity_id"].start_with?("#{domain}.") }
  end

  def entity_state(entity_id)
    entity(entity_id)&.dig("state")
  end

  def set_entity_state(entity_id, state, attributes = {})
    set_state(entity_id, state, attributes)
    { "entity_id" => entity_id, "state" => state.to_s }
  end

  def call_service(domain, service, data = {})
    @service_calls << { domain: domain.to_s, service: service.to_s, data: data }
    apply_service_effect(service.to_s, data)
    {}
  end

  def turn_on(entity_id, **options)
    call_service(entity_domain(entity_id), "turn_on", { entity_id: entity_id }.merge(options))
  end

  def turn_off(entity_id, **options)
    call_service(entity_domain(entity_id), "turn_off", { entity_id: entity_id }.merge(options))
  end

  def toggle(entity_id, **options)
    call_service(entity_domain(entity_id), "toggle", { entity_id: entity_id }.merge(options))
  end

  def services
    []
  end

  def domain_services(_domain)
    {}
  end

  def available?
    true
  end

  def config
    { "version" => "fake", "location_name" => "Fake Cube" }
  end

  def events
    []
  end

  def fire_event(event_type, data = {})
    @fired_events << { event_type: event_type.to_s, data: data }
    {}
  end

  def conversation_process(text:, agent_id: nil, conversation_id: nil)
    @conversation_requests << { text: text, agent_id: agent_id, conversation_id: conversation_id }
    @conversation_response || { "response" => { "speech" => { "plain" => { "speech" => "ok" } } } }
  end

  def send_conversation_response(response_data)
    speech = response_data.dig(:response, :speech, :plain, :speech) ||
             response_data.dig("response", "speech", "plain", "speech")
    return { error: "No speech text found in response data" } unless speech

    conversation_process(
      text: speech,
      conversation_id: response_data[:conversation_id] || response_data["conversation_id"]
    )
  end

  def history(_entity_id, _start_time = nil, _end_time = nil)
    []
  end

  private

  # Reflect turn_on/turn_off in the in-memory world so reads after a service call
  # see the change (good enough for scenarios; not a full HA state machine).
  def apply_service_effect(service, data)
    ids = Array(data[:entity_id] || data["entity_id"])
    case service
    when "turn_on"
      extra = stringify(data).except("entity_id")
      ids.each { |id| set_state(id, "on", (entity(id)&.dig("attributes") || {}).merge(extra)) }
    when "turn_off"
      ids.each { |id| set_state(id, "off") }
    when "set_value"
      value = data[:value] || data["value"]
      ids.each { |id| set_state(id, value) }
    end
  end

  def entity_domain(entity_id)
    entity_id.to_s.split(".").first
  end

  def stringify(hash)
    (hash || {}).transform_keys(&:to_s)
  end
end
