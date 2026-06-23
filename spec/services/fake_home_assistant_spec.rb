# frozen_string_literal: true

require "rails_helper"

# Unit spec for FakeHomeAssistant: the in-memory stand-in for HomeAssistantService
# used by the scenario harness. We test its ACTUAL behavior as written — state
# tracking, service-call recording, scripting helpers, and the drop-in contract.
RSpec.describe FakeHomeAssistant, type: :service do
  subject(:fake) { described_class.new }

  describe "#initialize" do
    it "starts with empty recording buffers" do
      fresh = described_class.new

      expect(fresh.service_calls).to eq([])
      expect(fresh.conversation_requests).to eq([])
      expect(fresh.fired_events).to eq([])
    end

    it "seeds the persona into input_select.current_persona by default (buddy)" do
      expect(fake.entity_state("input_select.current_persona")).to eq("buddy")
    end

    it "honors a custom persona" do
      fresh = described_class.new(persona: "jax")

      expect(fresh.entity_state("input_select.current_persona")).to eq("jax")
    end

    it "does not seed a persona entity when persona is nil" do
      fresh = described_class.new(persona: nil)

      expect(fresh.entity("input_select.current_persona")).to be_nil
    end

    it "seeds entities from the entities hash, defaulting state to 'on'" do
      fresh = described_class.new(
        persona: nil,
        entities: { "light.cube_inner" => { "state" => "off" } }
      )

      expect(fresh.entity_state("light.cube_inner")).to eq("off")
    end

    it "defaults a seeded entity with no state to 'on'" do
      fresh = described_class.new(persona: nil, entities: { "light.cube_inner" => {} })

      expect(fresh.entity_state("light.cube_inner")).to eq("on")
    end

    it "accepts symbol keys in the entities hash and stringifies them" do
      fresh = described_class.new(
        persona: nil,
        entities: { "light.cube_inner" => { state: "off", attributes: { brightness: 50 } } }
      )

      entity = fresh.entity("light.cube_inner")
      expect(entity["state"]).to eq("off")
      expect(entity["attributes"]).to eq("brightness" => 50)
    end
  end

  describe "#set_state" do
    it "stores a normalized entity hash with stringified state" do
      fake.set_state("light.cube_inner", :on)

      entity = fake.entity("light.cube_inner")
      expect(entity).to eq(
        "entity_id" => "light.cube_inner",
        "state" => "on",
        "attributes" => {}
      )
    end

    it "stringifies attribute keys" do
      fake.set_state("light.cube_inner", "on", { brightness: 200 })

      expect(fake.entity("light.cube_inner")["attributes"]).to eq("brightness" => 200)
    end

    it "overwrites a previously stored entity" do
      fake.set_state("light.cube_inner", "on")
      fake.set_state("light.cube_inner", "off")

      expect(fake.entity_state("light.cube_inner")).to eq("off")
    end
  end

  describe "#persona=" do
    it "writes the persona into input_select.current_persona" do
      fake.persona = "zorp"

      expect(fake.entity_state("input_select.current_persona")).to eq("zorp")
    end
  end

  describe "#conversation_response=" do
    it "overrides the canned conversation reply" do
      fake.conversation_response = { "custom" => "reply" }

      expect(fake.conversation_process(text: "hi")).to eq("custom" => "reply")
    end
  end

  describe "#entities" do
    it "returns dup'd copies of all stored entities" do
      fresh = described_class.new(persona: nil)
      fresh.set_state("light.cube_inner", "on")

      entities = fresh.entities
      expect(entities.size).to eq(1)
      expect(entities.first["entity_id"]).to eq("light.cube_inner")
    end

    it "returns copies that do not mutate internal state" do
      fresh = described_class.new(persona: nil)
      fresh.set_state("light.cube_inner", "on")

      fresh.entities.first["state"] = "tampered"

      expect(fresh.entity_state("light.cube_inner")).to eq("on")
    end
  end

  describe "#entity" do
    it "returns a dup of the requested entity" do
      fake.set_state("light.cube_inner", "on")

      expect(fake.entity("light.cube_inner")).to include("entity_id" => "light.cube_inner")
    end

    it "returns nil for an unknown entity" do
      expect(fake.entity("light.nonexistent")).to be_nil
    end

    it "returns a copy that does not mutate internal state" do
      fake.set_state("light.cube_inner", "on")

      fake.entity("light.cube_inner")["state"] = "tampered"

      expect(fake.entity_state("light.cube_inner")).to eq("on")
    end
  end

  describe "#entities_by_domain" do
    before do
      fake.set_state("light.cube_inner", "on")
      fake.set_state("light.cube_outer", "off")
      fake.set_state("media_player.cube", "playing")
    end

    it "returns only entities whose id starts with the domain prefix" do
      lights = fake.entities_by_domain("light")

      ids = lights.map { |e| e["entity_id"] }
      expect(ids).to contain_exactly("light.cube_inner", "light.cube_outer")
    end

    it "returns an empty array for a domain with no entities" do
      expect(fake.entities_by_domain("switch")).to eq([])
    end
  end

  describe "#entity_state" do
    it "returns the state string for a known entity" do
      fake.set_state("light.cube_inner", "on")

      expect(fake.entity_state("light.cube_inner")).to eq("on")
    end

    it "returns nil for an unknown entity" do
      expect(fake.entity_state("light.nope")).to be_nil
    end
  end

  describe "#set_entity_state" do
    it "stores the state and returns an id/state summary hash" do
      result = fake.set_entity_state("light.cube_inner", :on)

      expect(result).to eq("entity_id" => "light.cube_inner", "state" => "on")
      expect(fake.entity_state("light.cube_inner")).to eq("on")
    end

    it "persists attributes passed in" do
      fake.set_entity_state("light.cube_inner", "on", { brightness: 10 })

      expect(fake.entity("light.cube_inner")["attributes"]).to eq("brightness" => 10)
    end
  end

  describe "#call_service" do
    it "records the call with stringified domain and service" do
      fake.call_service(:light, :turn_on, { entity_id: "light.cube_inner" })

      expect(fake.service_calls).to eq([
        { domain: "light", service: "turn_on", data: { entity_id: "light.cube_inner" } }
      ])
    end

    it "returns an empty hash" do
      expect(fake.call_service("light", "turn_on")).to eq({})
    end

    it "applies a turn_on effect to the in-memory world" do
      fake.call_service("light", "turn_on", { entity_id: "light.cube_inner" })

      expect(fake.entity_state("light.cube_inner")).to eq("on")
    end

    it "merges non-entity_id data into attributes on turn_on" do
      fake.set_state("light.cube_inner", "off", { existing: "kept" })
      fake.call_service("light", "turn_on", { entity_id: "light.cube_inner", "rgb_color" => [255, 0, 0] })

      attributes = fake.entity("light.cube_inner")["attributes"]
      expect(attributes).to include("existing" => "kept", "rgb_color" => [255, 0, 0])
      expect(attributes).not_to have_key("entity_id")
    end

    it "applies a turn_off effect and clears the state" do
      fake.set_state("light.cube_inner", "on")
      fake.call_service("light", "turn_off", { entity_id: "light.cube_inner" })

      expect(fake.entity_state("light.cube_inner")).to eq("off")
    end

    it "applies the effect to multiple entity_ids" do
      fake.call_service("light", "turn_on", { entity_id: ["light.a", "light.b"] })

      expect(fake.entity_state("light.a")).to eq("on")
      expect(fake.entity_state("light.b")).to eq("on")
    end

    it "records but does not apply world effects for unknown services" do
      fake.set_state("light.cube_inner", "off")
      fake.call_service("light", "flash", { entity_id: "light.cube_inner" })

      expect(fake.service_calls_for("light").map { |c| c[:service] }).to eq(["flash"])
      expect(fake.entity_state("light.cube_inner")).to eq("off")
    end
  end

  describe "#service_calls_for" do
    before do
      fake.call_service("light", "turn_on", { entity_id: "light.cube_inner" })
      fake.call_service("media_player", "play_media", { entity_id: "media_player.cube" })
      fake.call_service("light", "turn_off", { entity_id: "light.cube_inner" })
    end

    it "filters recorded calls by domain" do
      light_calls = fake.service_calls_for("light")

      expect(light_calls.map { |c| c[:service] }).to eq(["turn_on", "turn_off"])
    end

    it "accepts a symbol domain" do
      expect(fake.service_calls_for(:media_player).size).to eq(1)
    end

    it "returns an empty array for an unused domain" do
      expect(fake.service_calls_for("switch")).to eq([])
    end
  end

  describe "#turn_on" do
    it "records a turn_on call on the entity's domain and turns it on" do
      fake.turn_on("light.cube_inner", brightness: 255)

      call = fake.service_calls.last
      expect(call[:domain]).to eq("light")
      expect(call[:service]).to eq("turn_on")
      expect(call[:data]).to eq(entity_id: "light.cube_inner", brightness: 255)
      expect(fake.entity_state("light.cube_inner")).to eq("on")
    end
  end

  describe "#turn_off" do
    it "records a turn_off call and turns the entity off" do
      fake.set_state("light.cube_inner", "on")
      fake.turn_off("light.cube_inner")

      call = fake.service_calls.last
      expect(call[:domain]).to eq("light")
      expect(call[:service]).to eq("turn_off")
      expect(fake.entity_state("light.cube_inner")).to eq("off")
    end
  end

  describe "#toggle" do
    it "records a toggle call on the entity's domain" do
      fake.toggle("light.cube_inner")

      call = fake.service_calls.last
      expect(call[:domain]).to eq("light")
      expect(call[:service]).to eq("toggle")
      expect(call[:data]).to eq(entity_id: "light.cube_inner")
    end

    it "does not change state because toggle has no world effect" do
      fake.set_state("light.cube_inner", "on")
      fake.toggle("light.cube_inner")

      expect(fake.entity_state("light.cube_inner")).to eq("on")
    end
  end

  describe "static drop-in interface stubs" do
    it "#services returns an empty array" do
      expect(fake.services).to eq([])
    end

    it "#domain_services returns an empty hash" do
      expect(fake.domain_services("light")).to eq({})
    end

    it "#available? is always true" do
      expect(fake.available?).to be(true)
    end

    it "#config returns the fake config metadata" do
      expect(fake.config).to eq("version" => "fake", "location_name" => "Fake Cube")
    end

    it "#events returns an empty array" do
      expect(fake.events).to eq([])
    end

    it "#history returns an empty array regardless of arguments" do
      expect(fake.history("sensor.foo")).to eq([])
      expect(fake.history("sensor.foo", "start", "end")).to eq([])
    end
  end

  describe "#fire_event" do
    it "records the event with a stringified type and returns an empty hash" do
      result = fake.fire_event(:custom_event, { foo: "bar" })

      expect(result).to eq({})
      expect(fake.fired_events).to eq([
        { event_type: "custom_event", data: { foo: "bar" } }
      ])
    end

    it "defaults data to an empty hash" do
      fake.fire_event("ping")

      expect(fake.fired_events.last).to eq(event_type: "ping", data: {})
    end
  end

  describe "#conversation_process" do
    it "records the request with all provided keys" do
      fake.conversation_process(text: "hello", agent_id: "agent.cube", conversation_id: "c1")

      expect(fake.conversation_requests).to eq([
        { text: "hello", agent_id: "agent.cube", conversation_id: "c1" }
      ])
    end

    it "returns the default canned response when none is configured" do
      expect(fake.conversation_process(text: "hi")).to eq(
        "response" => { "speech" => { "plain" => { "speech" => "ok" } } }
      )
    end

    it "returns the configured canned response when set" do
      configured = described_class.new(conversation_response: { "response" => "scripted" })

      expect(configured.conversation_process(text: "hi")).to eq("response" => "scripted")
    end
  end

  describe "#send_conversation_response" do
    let(:response_data) do
      { response: { speech: { plain: { speech: "I am the cube" } } }, conversation_id: "c9" }
    end

    it "extracts speech from a symbol-keyed payload and forwards it to conversation_process" do
      result = fake.send_conversation_response(response_data)

      expect(result).to eq("response" => { "speech" => { "plain" => { "speech" => "ok" } } })
      expect(fake.conversation_requests).to eq([
        { text: "I am the cube", agent_id: nil, conversation_id: "c9" }
      ])
    end

    it "extracts speech from a string-keyed payload" do
      string_payload = {
        "response" => { "speech" => { "plain" => { "speech" => "hello there" } } },
        "conversation_id" => "c10"
      }

      fake.send_conversation_response(string_payload)

      expect(fake.conversation_requests.last).to eq(
        text: "hello there", agent_id: nil, conversation_id: "c10"
      )
    end

    it "returns an error and records nothing when no speech text is present" do
      result = fake.send_conversation_response({ response: { speech: {} } })

      expect(result).to eq(error: "No speech text found in response data")
      expect(fake.conversation_requests).to eq([])
    end
  end

  describe "drop-in-for-HomeAssistantService contract" do
    # The fake is injected via the singleton seam and class-method delegation,
    # so a class call like HomeAssistantService.entity must reach the fake.
    let(:fake) do
      described_class.new(
        persona: "jax",
        entities: { "light.cube_inner" => { "state" => "on" } }
      )
    end

    around do |example|
      HomeAssistantService.instance = fake
      example.run
      HomeAssistantService.reset_instance!
    end

    it "answers class-level entity lookups via delegation", :allow_ha_calls do
      expect(HomeAssistantService.entity("light.cube_inner")).to include("state" => "on")
    end

    it "records class-level service calls on the fake", :allow_ha_calls do
      HomeAssistantService.call_service("light", "turn_off", { entity_id: "light.cube_inner" })

      expect(fake.service_calls_for("light").map { |c| c[:service] }).to eq(["turn_off"])
      expect(HomeAssistantService.entity_state("light.cube_inner")).to eq("off")
    end

    it "reports availability through the class", :allow_ha_calls do
      expect(HomeAssistantService.available?).to be(true)
    end
  end
end
