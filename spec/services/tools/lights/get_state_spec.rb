# spec/services/tools/lights/get_state_spec.rb
require 'rails_helper'

RSpec.describe Tools::Lights::GetState do
  let(:mock_service) { instance_double(HomeAssistantService) }
  
  before do
    allow(HomeAssistantService).to receive(:instance).and_return(mock_service)
    allow(HomeAssistantService).to receive(:entities).and_return([
      { 'entity_id' => 'light.cube_voice_ring', 'state' => 'on' }
    ])
  end

  describe '.tool_type' do
    it 'returns sync execution type' do
      expect(described_class.tool_type).to eq(:sync)
    end
  end

  describe '#call' do
    let(:tool) { described_class.new }
    let(:valid_entity_id) { 'light.cube_voice_ring' }
    let(:entity_data) do
      {
        'state' => 'on',
        'last_updated' => '2025-08-17T18:33:57.706916+00:00',
        'last_changed' => '2025-08-16T15:46:59.659006+00:00',
        'attributes' => {
          'brightness' => 255,
          'rgb_color' => [255, 0, 0],
          'hs_color' => [0.0, 100.0],
          'supported_color_modes' => ['rgb'],
          'supported_features' => 40
        }
      }
    end
    
    before do
      # Mock the service boundary
      allow(HomeAssistantService).to receive(:entity).and_return(entity_data)
    end

    context 'with valid entity_id' do
      it 'calls HomeAssistantService.entity with correct parameter' do
        expect(HomeAssistantService).to receive(:entity).with(valid_entity_id)

        tool.call(entity_id: valid_entity_id)
      end

      it 'returns success response with complete state information' do
        result = tool.call(entity_id: valid_entity_id)
        
        expect(result).to include(
          success: true,
          entity_id: valid_entity_id,
          state: 'on',
          is_on: true
        )
        
        expect(result[:brightness]).to include(
          raw_value: 255,
          percentage: 100
        )
        
        expect(result[:color]).to include(
          rgb: [255, 0, 0],
          rgb_string: 'RGB(255, 0, 0)',
          hue_saturation: [0.0, 100.0]
        )
      end

      it 'handles entity without brightness' do
        entity_data['attributes'].delete('brightness')
        
        result = tool.call(entity_id: valid_entity_id)
        
        expect(result[:success]).to be true
        expect(result[:brightness]).to be_nil
      end

      it 'handles entity without color' do
        entity_data['attributes'].delete('rgb_color')
        entity_data['attributes'].delete('hs_color')
        
        result = tool.call(entity_id: valid_entity_id)
        
        expect(result[:success]).to be true
        expect(result[:color]).to be_nil
      end
    end

    context 'when entity not found' do
      before do
        allow(HomeAssistantService).to receive(:entity).and_return(nil)
      end

      it 'returns error response' do
        result = tool.call(entity_id: valid_entity_id)
        
        expect(result).to include(
          success: false,
          error: a_string_including('Could not retrieve state')
        )
      end
    end

    context 'when HomeAssistantService raises error' do
      before do
        allow(HomeAssistantService).to receive(:entity).and_raise(
          HomeAssistantService::Error.new('Connection failed')
        )
      end

      it 'returns error response' do
        result = tool.call(entity_id: valid_entity_id)
        
        expect(result).to include(
          success: false,
          error: a_string_including('Failed to get light state')
        )
      end
    end
  end
end