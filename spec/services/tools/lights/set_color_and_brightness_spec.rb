# spec/services/tools/lights/set_color_and_brightness_spec.rb
require 'rails_helper'

RSpec.describe Tools::Lights::SetColorAndBrightness do
  let(:mock_service) { instance_double(HomeAssistantService) }
  
  before do
    allow(HomeAssistantService).to receive(:instance).and_return(mock_service)
    allow(HomeAssistantService).to receive(:entities).and_return([
      { 'entity_id' => 'light.cube_voice_ring', 'state' => 'off' }
    ])
    allow(HomeAssistantService).to receive(:call_service).and_return({ 'success' => true })
  end

  describe '#call' do
    let(:tool) { described_class.new }
    let(:valid_entity_id) { 'light.cube_voice_ring' }
    
    context 'with RGB color only' do
      it 'calls HomeAssistantService with correct RGB parameters' do
        expect(HomeAssistantService).to receive(:call_service).with(
          'light',
          'turn_on',
          { entity_id: valid_entity_id, rgb_color: [255, 0, 0] }
        )

        tool.call(entity_id: valid_entity_id, rgb_color: [255, 0, 0])
      end
    end

    context 'with brightness only' do
      it 'calls HomeAssistantService with correct brightness parameters' do
        expect(HomeAssistantService).to receive(:call_service).with(
          'light',
          'turn_on',
          { entity_id: valid_entity_id, brightness: 128 }
        )

        tool.call(entity_id: valid_entity_id, brightness_percent: 50)
      end
    end

    context 'with both color and brightness' do
      it 'calls HomeAssistantService with both parameters' do
        expect(HomeAssistantService).to receive(:call_service).with(
          'light',
          'turn_on',
          { 
            entity_id: valid_entity_id, 
            rgb_color: [255, 128, 0], 
            brightness: 191 
          }
        )

        tool.call(
          entity_id: valid_entity_id, 
          rgb_color: [255, 128, 0], 
          brightness_percent: 75
        )
      end
    end

    context 'with transition time' do
      it 'includes transition in service call' do
        expect(HomeAssistantService).to receive(:call_service).with(
          'light',
          'turn_on',
          { 
            entity_id: valid_entity_id, 
            rgb_color: [0, 255, 0], 
            transition: 2.5 
          }
        )

        tool.call(
          entity_id: valid_entity_id, 
          rgb_color: [0, 255, 0], 
          transition: 2.5
        )
      end
    end

    context 'with invalid parameters' do
      it 'returns error when no color or brightness provided' do
        result = tool.call(entity_id: valid_entity_id)
        
        expect(result).to include(
          success: false,
          error: a_string_including('Must specify rgb_color, brightness_percent, or both')
        )
      end

      it 'returns error for invalid RGB color' do
        result = tool.call(entity_id: valid_entity_id, rgb_color: [300, 0, 0])
        
        expect(result).to include(
          success: false,
          error: a_string_including('Invalid rgb_color')
        )
      end

      it 'returns error for invalid brightness' do
        result = tool.call(entity_id: valid_entity_id, brightness_percent: 150)
        
        expect(result).to include(
          success: false,
          error: a_string_including('Invalid brightness_percent')
        )
      end

      it 'returns error for malformed RGB array' do
        result = tool.call(entity_id: valid_entity_id, rgb_color: [255, 0])
        
        expect(result).to include(
          success: false,
          error: a_string_including('Invalid rgb_color')
        )
      end
    end

    context 'successful execution' do
      it 'returns success response with applied values' do
        result = tool.call(
          entity_id: valid_entity_id, 
          rgb_color: [255, 0, 0], 
          brightness_percent: 80
        )
        
        expect(result).to include(
          success: true,
          entity_id: valid_entity_id,
          rgb_color: [255, 0, 0],
          brightness_percent: 80
        )
        
        expect(result[:message]).to include('color: RGB(255, 0, 0)')
        expect(result[:message]).to include('brightness: 80%')
      end
    end
  end
end