# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Personas::JaxPersona, type: :model do
  let(:persona) { described_class.new }

  describe '#persona_id' do
    it 'returns :jax' do
      expect(persona.persona_id).to eq(:jax)
    end
  end

  describe '#name' do
    it 'returns "Jax"' do
      expect(persona.name).to eq("Jax")
    end
  end

  describe '#personality_traits' do
    it 'includes bartender traits from config' do
      expect(persona.personality_traits).to include("grumpy", "nostalgic", "music-purist", "bartender-wise")
    end
  end

  describe '#available_tools' do
    it 'includes SearchMusicTool as specified in base_tools includes' do
      tools = persona.available_tools
      expect(tools).to include("SearchMusicTool")
      expect(tools).to include("LightingTool", "MusicTool", "EffectsTool")
    end
  end

  describe '#response_style' do
    it 'includes bartender characteristics' do
      style = persona.response_style
      expect(style[:tone]).to eq("gruff_bartender")
      expect(style[:formality]).to eq("bar_casual")
      expect(style[:verbosity]).to eq("monologue_prone")
      expect(style[:space_western_slang]).to be true
    end
  end

  describe '#can_handle_topic?' do
    it 'handles music topics with expertise' do
      music_topics = [ "music", "band", "song", "album", "vinyl" ]
      music_topics.each do |topic|
        expect(persona.can_handle_topic?(topic)).to be true
      end
    end

    it 'handles bartending and life advice topics' do
      bartender_topics = [ "advice", "relationship", "problem", "drink", "bar" ]
      bartender_topics.each do |topic|
        expect(persona.can_handle_topic?(topic)).to be true
      end
    end
  end

  describe '#process_message' do
    context 'with music-related message' do
      it 'includes music-focused context' do
        result = persona.process_message("Play some real music, none of that electronic crap", {})

        expect(result).to include(:system_prompt, :available_tools, :context)
        expect(result[:context][:grumpy_level]).to be_between(7, 11)
        expect(result[:context][:music_purist_mode]).to be true
      end
    end

    context 'with electronic music mention' do
      it 'triggers anti-electronic context' do
        result = persona.process_message("I love EDM!", {})

        expect(result[:context][:anti_electronic_rant]).to be true
        expect(result[:context][:grumpy_level]).to be >= 8
      end
    end
  end

  describe 'YAML configuration loading' do
    let(:mock_config) do
      {
        "name" => "Jax",
        "voice_id" => "TonyNeural||unfriendly",
        "agent_id" => "01k2cz5js7swgtczvr5cpxeksn",
        "base_tools" => {
          "includes" => [ "SearchMusicTool" ],
          "excludes" => []
        },
        "available_tools" => [ "LightingTool", "MusicTool", "SearchMusicTool", "EffectsTool" ],
        "traits" => [ "grumpy", "nostalgic", "music-purist", "bartender-wise" ]
      }
    end

    before do
      expect(YAML).to receive(:load_file).and_return(mock_config)
    end

    it 'loads configuration from jax.yml' do
      expect(persona.send(:persona_config)["name"]).to eq("Jax")
    end

    it 'respects base_tools includes configuration' do
      expect(persona.available_tools).to include("SearchMusicTool")
    end
  end
end
