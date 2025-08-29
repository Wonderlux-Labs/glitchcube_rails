# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CubeData::Lights do
  let(:mock_ha_service) { instance_double(HomeAssistantService) }

  before do
    allow(CubeData).to receive(:ha_service).and_return(mock_ha_service)
    allow(CubeData).to receive(:call_service).and_return(true)
    allow(CubeData).to receive(:read_sensor).and_return(nil)
  end

  describe '.turn_on' do
    it 'turns on light with basic parameters' do
      expect(CubeData).to receive(:call_service)
        .with("light", "turn_on", { entity_id: "light.cube_light_top" })

      CubeData::Lights.turn_on("light.cube_light_top")
    end

    it 'turns on light with brightness and color' do
      expect(CubeData).to receive(:call_service)
        .with(
          "light",
          "turn_on",
          {
            entity_id: "light.cube_light_top",
            brightness: 255,
            rgb_color: [ 255, 0, 0 ],
            effect: "rainbow"
          }
        )

      CubeData::Lights.turn_on(
        "light.cube_light_top",
        brightness: 255,
        color: [ 255, 0, 0 ],
        effect: "rainbow"
      )
    end

    it 'normalizes light entity IDs from symbols' do
      expect(CubeData).to receive(:call_service)
        .with("light", "turn_on", { entity_id: "light.cube_light_top" })

      CubeData::Lights.turn_on(:top)
    end
  end

  describe '.turn_off' do
    it 'turns off light' do
      expect(CubeData).to receive(:call_service)
        .with("light", "turn_off", { entity_id: "light.cube_inner" })

      CubeData::Lights.turn_off("light.cube_inner")
    end

    it 'turns off light with transition' do
      expect(CubeData).to receive(:call_service)
        .with("light", "turn_off", { entity_id: "light.cube_inner", transition: 5 })

      CubeData::Lights.turn_off("light.cube_inner", transition: 5)
    end
  end

  describe '.get_state' do
    let(:light_state) do
      {
        "state" => "on",
        "attributes" => {
          "brightness" => 200,
          "rgb_color" => [ 255, 255, 255 ],
          "effect" => "solid"
        }
      }
    end

    it 'gets light state with short cache TTL' do
      expect(CubeData).to receive(:read_sensor)
        .with("light.cube_light_top", cache_ttl: 1.second)
        .and_return(light_state)

      result = CubeData::Lights.get_state("light.cube_light_top")
      expect(result).to eq(light_state)
    end
  end

  describe '.on?' do
    it 'returns true when light state is on' do
      light_state = { "state" => "on" }
      expect(CubeData).to receive(:read_sensor).and_return(light_state)

      expect(CubeData::Lights.on?("light.cube_light_top")).to be true
    end

    it 'returns false when light state is off' do
      light_state = { "state" => "off" }
      expect(CubeData).to receive(:read_sensor).and_return(light_state)

      expect(CubeData::Lights.on?("light.cube_light_top")).to be false
    end
  end

  describe '.brightness' do
    it 'returns brightness value from attributes' do
      light_state = {
        "state" => "on",
        "attributes" => { "brightness" => 150 }
      }
      expect(CubeData).to receive(:read_sensor).and_return(light_state)

      expect(CubeData::Lights.brightness("light.cube_light_top")).to eq(150)
    end

    it 'returns 0 when no brightness attribute' do
      light_state = { "state" => "on", "attributes" => {} }
      expect(CubeData).to receive(:read_sensor).and_return(light_state)

      expect(CubeData::Lights.brightness("light.cube_light_top")).to eq(0)
    end
  end

  describe '.all_on' do
    it 'turns on all cube lights with same parameters' do
      expect(CubeData::Lights).to receive(:turn_on)
        .with("light.cube_light_top", brightness: 255, effect: "rainbow")
      expect(CubeData::Lights).to receive(:turn_on)
        .with("light.cube_inner", brightness: 255, effect: "rainbow")

      CubeData::Lights.all_on(brightness: 255, effect: "rainbow")
    end
  end

  describe '.sync_effect' do
    it 'applies same effect to all lights' do
      expect(CubeData::Lights).to receive(:all_on)
        .with(brightness: 200, effect: "pulse", transition: 2)

      CubeData::Lights.sync_effect("pulse", brightness: 200, transition: 2)
    end
  end

  describe '.available_effects' do
    it 'returns effect list from light attributes' do
      light_state = {
        "state" => "on",
        "attributes" => {
          "effect_list" => [ "solid", "rainbow", "pulse", "strobe" ]
        }
      }
      expect(CubeData).to receive(:read_sensor).and_return(light_state)

      effects = CubeData::Lights.available_effects("light.cube_light_top")
      expect(effects).to eq([ "solid", "rainbow", "pulse", "strobe" ])
    end
  end
end
