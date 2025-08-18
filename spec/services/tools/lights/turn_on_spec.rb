# spec/services/tools/lights/turn_on_spec.rb
require 'rails_helper'

RSpec.describe Tools::Lights::TurnOn do
  let(:mock_service) { instance_double(HomeAssistantService) }

  before do
    allow(HomeAssistantService).to receive(:instance).and_return(mock_service)
    allow(mock_service).to receive(:entities).and_return([
      { 'entity_id' => 'light.cube_voice_ring', 'state' => 'off' },
      { 'entity_id' => 'light.cube_inner', 'state' => 'on' }
    ])
  end

  describe '.definition' do
    it 'returns OpenRouter tool definition' do
      definition = described_class.definition
      expect(definition).to respond_to(:name)
    end
  end

  describe '.description' do
    it 'returns human-readable description' do
      expect(described_class.description).to be_a(String)
      expect(described_class.description).to include('Turn on cube lights')
    end
  end

  describe '.prompt_schema' do
    it 'returns prompt-friendly schema' do
      expect(described_class.prompt_schema).to be_a(String)
      expect(described_class.prompt_schema).to include('turn_on_light')
    end
  end

  describe '.tool_type' do
    it 'returns async execution type' do
      expect(described_class.tool_type).to eq(:async)
    end
  end

  describe '.available_entities' do
    it 'returns cube light entities' do
      expect(described_class.available_entities).to eq(Tools::BaseTool::CUBE_LIGHT_ENTITIES)
    end
  end

  describe '#call' do
    let(:tool) { described_class.new }
    let(:valid_entity_id) { 'light.cube_voice_ring' }

    before do
      # Mock the service boundary
      allow(mock_service).to receive(:call_service).and_return({ 'success' => true })
    end

    context 'with valid entity_id' do
      it 'calls HomeAssistantService with correct parameters' do
        expect(mock_service).to receive(:call_service).with(
          'light',
          'turn_on',
          { entity_id: valid_entity_id }
        )

        result = tool.call(entity_id: valid_entity_id)
        expect(result[:success]).to be true
      end

      it 'includes transition when provided' do
        expect(mock_service).to receive(:call_service).with(
          'light',
          'turn_on',
          { entity_id: valid_entity_id, transition: 2.0 }
        )

        tool.call(entity_id: valid_entity_id, transition: 2.0)
      end

      it 'returns success response with correct structure' do
        result = tool.call(entity_id: valid_entity_id)

        expect(result).to include(
          success: true,
          message: a_string_including('Turned on'),
          entity_id: valid_entity_id
        )
      end
    end

    context 'with invalid entity_id' do
      it 'returns error for non-existent entity' do
        result = tool.call(entity_id: 'light.nonexistent')

        expect(result).to include(
          error: a_string_including('not found')
        )
        expect(result).to have_key(:available_entities)
      end

      it 'returns error for non-cube light' do
        # Add living room to mock entities first so validation passes
        allow(mock_service).to receive(:entities).and_return([
          { 'entity_id' => 'light.cube_voice_ring', 'state' => 'off' },
          { 'entity_id' => 'light.cube_inner', 'state' => 'on' },
          { 'entity_id' => 'light.living_room', 'state' => 'on' }
        ])

        result = tool.call(entity_id: 'light.living_room')

        expect(result).to include(
          success: false,
          error: a_string_including('not a cube light')
        )
      end
    end

    context 'when HomeAssistantService raises error' do
      before do
        allow(mock_service).to receive(:call_service).and_raise(
          HomeAssistantService::Error.new('Connection failed')
        )
      end

      it 'returns error response' do
        result = tool.call(entity_id: valid_entity_id)

        expect(result).to include(
          success: false,
          error: a_string_including('Failed to turn on light')
        )
      end
    end
  end
end
