# spec/services/tools/registry_spec.rb
require 'rails_helper'

RSpec.describe Tools::Registry do
  describe '.all_tools' do
    it 'returns hash of all available tools' do
      tools = described_class.all_tools

      expect(tools).to be_a(Hash)
      expect(tools.keys).to include(
        'turn_on_light',
        'turn_off_light',
        'set_light_color_and_brightness',
        'get_light_state',
        'list_light_effects',
        'set_light_effect'
      )
    end

    it 'returns tool classes that respond to required methods' do
      described_class.all_tools.each do |name, tool_class|
        expect(tool_class).to respond_to(:definition)
        expect(tool_class).to respond_to(:description)
        expect(tool_class).to respond_to(:prompt_schema)
        expect(tool_class).to respond_to(:tool_type)
        expect(tool_class).to respond_to(:call)
      end
    end
  end

  describe '.sync_tools' do
    it 'returns only sync tools' do
      sync_tools = described_class.sync_tools

      expect(sync_tools.keys).to include('get_light_state', 'list_light_effects')
      expect(sync_tools.keys).not_to include('turn_on_light', 'turn_off_light')
    end
  end

  describe '.async_tools' do
    it 'returns only async tools' do
      async_tools = described_class.async_tools

      expect(async_tools.keys).to include(
        'turn_on_light',
        'turn_off_light',
        'set_light_color_and_brightness',
        'set_light_effect'
      )
      expect(async_tools.keys).not_to include('get_light_state')
    end
  end

  describe '.get_tool' do
    it 'returns correct tool class for valid name' do
      tool_class = described_class.get_tool('turn_on_light')
      expect(tool_class).to eq(Tools::Lights::TurnOn)
    end

    it 'returns nil for invalid name' do
      tool_class = described_class.get_tool('nonexistent_tool')
      expect(tool_class).to be_nil
    end
  end

  describe '.execute_tool' do
    let(:mock_service) { instance_double(HomeAssistantService) }

    before do
      allow(HomeAssistantService).to receive(:instance).and_return(mock_service)
      allow(mock_service).to receive(:entities).and_return([
        { 'entity_id' => 'light.cube_voice_ring', 'state' => 'off' }
      ])
      allow(mock_service).to receive(:entity).and_return({
        'state' => 'on',
        'attributes' => { 'brightness' => 255 }
      })
    end

    it 'executes tool with correct arguments' do
      result = described_class.execute_tool('get_light_state', entity_id: 'light.cube_voice_ring')

      expect(result).to include(
        success: true,
        entity_id: 'light.cube_voice_ring'
      )
    end

    it 'returns error for unknown tool' do
      result = described_class.execute_tool('unknown_tool', some_arg: 'value')

      expect(result).to eq({ error: "Tool 'unknown_tool' not found" })
    end
  end

  describe '.prompt_tool_list' do
    it 'returns formatted tool list for prompts' do
      tool_list = described_class.prompt_tool_list

      expect(tool_list).to be_a(String)
      expect(tool_list).to include('turn_on_light(')
      expect(tool_list).to include('[async]')
      expect(tool_list).to include('[sync]')
    end
  end

  describe '.light_tools' do
    it 'returns only light-related tools' do
      light_tools = described_class.light_tools

      expect(light_tools.keys).to all(include('light'))
      expect(light_tools.keys).not_to include('play_music')
    end
  end

  describe '.cube_light_entities' do
    let(:mock_service_for_entities) { instance_double(HomeAssistantService) }

    before do
      # Mock Home Assistant service to return consistent test data
      allow(HomeAssistantService).to receive(:instance).and_return(mock_service_for_entities)
      allow(mock_service_for_entities).to receive(:entities).and_return([
        { 'entity_id' => 'light.cube_voice_ring', 'state' => 'off' },
        { 'entity_id' => 'light.cube_inner', 'state' => 'on' },
        { 'entity_id' => 'light.cube_top', 'state' => 'off' },
        { 'entity_id' => 'light.other_light', 'state' => 'on' }
      ])
    end

    it 'returns cube light entities from Home Assistant' do
      entities = described_class.cube_light_entities

      expect(entities).to include(
        'light.cube_voice_ring',
        'light.cube_inner',
        'light.cube_top'
      )
      expect(entities).not_to include('light.other_light')
      expect(entities).to eq(entities.sort)
    end
  end
end
