# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Personas::SparklePersona, type: :model do
  let(:persona) { described_class.new }

  describe '#persona_id' do
    it 'returns :sparkle' do
      expect(persona.persona_id).to eq(:sparkle)
    end
  end

  describe '#name' do
    it 'returns "Sparkle"' do
      expect(persona.name).to eq("Sparkle")
    end
  end

  describe '#personality_traits' do
    it 'includes childlike wonder traits from config' do
      expect(persona.personality_traits).to include("innocent", "enthusiastic", "wonder-filled", "literal-minded", "pure-hearted")
    end
  end

  describe '#available_tools' do
    context 'with base_tools excludes configuration' do
      it 'excludes MusicTool as specified in YML' do
        tools = persona.available_tools
        expect(tools).not_to include("MusicTool")
        expect(tools).to include("LightingTool", "EffectsTool")
      end
    end

    context 'when YML config is unavailable' do
      before do
        allow(persona).to receive(:load_persona_config).and_raise(StandardError.new("Config not found"))
      end

      it 'uses default config without MusicTool' do
        tools = persona.available_tools
        expect(tools).not_to include("MusicTool")
      end
    end
  end

  describe '#response_style' do
    it 'includes childlike characteristics' do
      style = persona.response_style
      expect(style[:tone]).to eq("childlike_wonder")
      expect(style[:formality]).to eq("very_casual")
      expect(style[:verbosity]).to eq("excited_rambling")
      expect(style[:exclamation_points]).to eq("excessive")
    end
  end

  describe '#can_handle_topic?' do
    it 'is enthusiastic about light-related topics' do
      light_topics = [ "light", "color", "sparkle", "bright", "rainbow", "glow" ]
      light_topics.each do |topic|
        expect(persona.can_handle_topic?(topic)).to be true
      end
    end

    it 'is willing to try any topic with enthusiasm' do
      random_topics = [ "cooking", "math", "space", "music" ]
      random_topics.each do |topic|
        expect(persona.can_handle_topic?(topic)).to be true
      end
    end
  end

  describe '#process_message' do
    it 'includes sparkle-specific context' do
      result = persona.process_message("Make me sparkle!", { test: "context" })

      expect(result).to include(:system_prompt, :available_tools, :context)
      expect(result[:context][:sparkle_mode]).to be true
      expect(result[:context][:excitement_level]).to be_between(5, 9)
    end
  end

  describe 'YAML configuration loading' do
    let(:mock_config) do
      {
        "name" => "Sparkle",
        "voice_id" => "cgSgspJ2msm6clMCkdW9",
        "agent_id" => "01k2yv6d7aq6q1s5z9dxht89bc",
        "base_tools" => {
          "includes" => [],
          "excludes" => [ "MusicTool" ]
        },
        "available_tools" => [ "LightingTool", "EffectsTool" ],
        "traits" => [ "innocent", "enthusiastic", "wonder-filled" ]
      }
    end

    before do
      expect(YAML).to receive(:load_file).and_return(mock_config)
    end

    it 'loads configuration from sparkle.yml' do
      expect(persona.send(:persona_config)["name"]).to eq("Sparkle")
    end

    it 'respects base_tools excludes configuration' do
      expect(persona.available_tools).not_to include("MusicTool")
    end
  end
end
