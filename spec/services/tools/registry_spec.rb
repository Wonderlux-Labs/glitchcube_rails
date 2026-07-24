# frozen_string_literal: true

require "rails_helper"

# The registry maps tool NAMES to classes and groups them into the two translator
# lanes (:action and :sound). It's how ToolCallingService selects which tools a lane's
# LLM may call, looks a call back up by name, and executes it.
RSpec.describe Tools::Registry, :allow_ha_calls do
  describe ".tools_for_lane" do
    it "puts lights, marquee, persona and announcement on the action lane" do
      names = Tools::Registry.tools_for_lane(:action).map { |t| t.definition.name }

      expect(names).to include(
        "set_cube_lights", "set_lights_to_dance_mode", "set_lights_to_jazz_mode",
        "show_marquee_message", "clear_marquee", "set_persona", "make_announcement"
      )
    end

    it "puts the jukebox tools on the sound lane" do
      names = Tools::Registry.tools_for_lane(:sound).map { |t| t.definition.name }

      expect(names).to contain_exactly("play_music", "play_sound_effect")
    end

    it "keeps the two lanes disjoint" do
      action = Tools::Registry.tools_for_lane(:action)
      sound = Tools::Registry.tools_for_lane(:sound)

      expect(action & sound).to be_empty
    end
  end

  describe ".tool_definitions_for_lane" do
    it "returns OpenRouter tool definitions for the lane" do
      definitions = Tools::Registry.tool_definitions_for_lane(:sound)

      expect(definitions).to all(be_a(OpenRouter::Tool))
      expect(definitions.map(&:name)).to include("play_music")
    end
  end

  describe ".get_tool / .definition_for" do
    it "looks a tool class up by name" do
      expect(Tools::Registry.get_tool("set_cube_lights")).to eq(Tools::Lights::SetLight)
    end

    it "returns the tool's definition by name (for validation)" do
      expect(Tools::Registry.definition_for("play_music").name).to eq("play_music")
    end

    it "returns nil for an unknown name" do
      expect(Tools::Registry.get_tool("nope")).to be_nil
    end
  end

  describe ".execute_tool" do
    let(:fake_ha) { FakeHomeAssistant.new }

    before { HomeAssistantService.instance = fake_ha }
    after { HomeAssistantService.reset_instance! }

    it "executes a tool by name, filtering blank args and symbolizing keys" do
      result = Tools::Registry.execute_tool("set_cube_lights", "led_strip" => "both", "color" => "", "effect" => "Aurora")

      expect(result[:success]).to be(true)
      vars = fake_ha.service_calls_for("script").last[:data][:variables]
      expect(vars.keys).to contain_exactly(:led_strip, :effect)
    end

    it "returns an error hash for an unknown tool" do
      result = Tools::Registry.execute_tool("nope", foo: "bar")

      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/not found/i)
    end
  end
end
