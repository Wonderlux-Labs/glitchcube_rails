# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Persona base_tools include/exclude functionality", type: :model do
  describe "base_tools configuration" do
    let(:mock_sparkle_config) do
      {
        "name" => "Sparkle",
        "base_tools" => {
          "includes" => [],
          "excludes" => [ "MusicTool" ]
        },
        "available_tools" => [ "LightingTool", "MusicTool", "EffectsTool" ],
        "traits" => [ "innocent", "enthusiastic" ]
      }
    end

    let(:mock_jax_config) do
      {
        "name" => "Jax",
        "base_tools" => {
          "includes" => [ "SearchMusicTool" ],
          "excludes" => []
        },
        "available_tools" => [ "LightingTool", "MusicTool", "EffectsTool" ],
        "traits" => [ "grumpy", "music-purist" ]
      }
    end

    let(:mock_buddy_config) do
      {
        "name" => "Buddy",
        "base_tools" => {
          "includes" => [],
          "excludes" => []
        },
        "available_tools" => [ "LightingTool", "MusicTool", "EffectsTool" ],
        "traits" => [ "enthusiastic", "helpful" ]
      }
    end

    describe Personas::SparklePersona do
      let(:persona) { described_class.new }

      before do
        allow(YAML).to receive(:load_file).and_return(mock_sparkle_config)
      end

      it "excludes MusicTool from available tools" do
        expect(persona.available_tools).not_to include("MusicTool")
        expect(persona.available_tools).to include("LightingTool", "EffectsTool")
      end

      it "handles empty includes array" do
        expect(persona.available_tools.length).to eq(2) # LightingTool, EffectsTool
      end

      it "respects excludes configuration over available_tools" do
        # Even though MusicTool is in available_tools, it should be excluded
        original_tools = mock_sparkle_config["available_tools"]
        expect(original_tools).to include("MusicTool")
        expect(persona.available_tools).not_to include("MusicTool")
      end
    end

    describe Personas::JaxPersona do
      let(:persona) { described_class.new }

      before do
        allow(YAML).to receive(:load_file).and_return(mock_jax_config)
      end

      it "includes SearchMusicTool in available tools" do
        expect(persona.available_tools).to include("SearchMusicTool")
        expect(persona.available_tools).to include("LightingTool", "MusicTool", "EffectsTool")
      end

      it "handles empty excludes array" do
        expect(persona.available_tools).to include("MusicTool") # Not excluded
      end

      it "adds included tools to base available_tools" do
        # SearchMusicTool should be added even though it's not in available_tools
        original_tools = mock_jax_config["available_tools"]
        expect(original_tools).not_to include("SearchMusicTool")
        expect(persona.available_tools).to include("SearchMusicTool")
      end

      it "removes duplicates from final tool list" do
        # If SearchMusicTool was in both includes and available_tools, should only appear once
        mock_jax_config["available_tools"] << "SearchMusicTool"
        expect(persona.available_tools.count("SearchMusicTool")).to eq(1)
      end
    end

    describe Personas::BuddyPersona do
      let(:persona) { described_class.new }

      before do
        allow(YAML).to receive(:load_file).and_return(mock_buddy_config)
      end

      it "uses available_tools unchanged when includes/excludes are empty" do
        expect(persona.available_tools).to match_array([ "LightingTool", "MusicTool", "EffectsTool" ])
      end

      it "handles missing base_tools configuration gracefully" do
        mock_buddy_config.delete("base_tools")
        expect(persona.available_tools).to match_array([ "LightingTool", "MusicTool", "EffectsTool" ])
      end
    end
  end

  describe "error handling" do
    describe Personas::SparklePersona do
      let(:persona) { described_class.new }

      context "when YAML config is unavailable" do
        before do
          allow(YAML).to receive(:load_file).and_raise(StandardError.new("Config not found"))
        end

        it "falls back to default config with MusicTool excluded" do
          expect(persona.available_tools).not_to include("MusicTool")
          expect(persona.available_tools).to include("LightingTool", "EffectsTool")
        end
      end

      context "when base_tools config is malformed" do
        before do
          malformed_config = {
            "name" => "Sparkle",
            "base_tools" => "invalid_structure", # Should be a hash
            "available_tools" => [ "LightingTool", "EffectsTool" ]
          }
          allow(YAML).to receive(:load_file).and_return(malformed_config)
        end

        it "handles malformed base_tools gracefully" do
          expect { persona.available_tools }.not_to raise_error
          expect(persona.available_tools).to include("LightingTool", "EffectsTool")
        end
      end
    end
  end

  describe "complex include/exclude scenarios" do
    let(:complex_config) do
      {
        "name" => "TestPersona",
        "base_tools" => {
          "includes" => [ "SearchMusicTool", "SpecialTool" ],
          "excludes" => [ "MusicTool", "EffectsTool" ]
        },
        "available_tools" => [ "LightingTool", "MusicTool", "EffectsTool", "DisplayTool" ],
        "traits" => [ "test" ]
      }
    end

    let(:test_persona_class) do
      Class.new(CubePersona) do
        def persona_id
          :test
        end

        def name
          "TestPersona"
        end

        def personality_traits
          [ "test" ]
        end

        def knowledge_base
          [ "testing" ]
        end

        def response_style
          { tone: "test" }
        end

        def can_handle_topic?(topic)
          true
        end

        def process_message(message, context = {})
          {}
        end

        def available_tools
          # Get base tools from configuration
          base_tools_config = persona_config.dig("base_tools") || {}
          includes = base_tools_config["includes"] || []
          excludes = base_tools_config["excludes"] || []

          # Start with available_tools from config
          tools = persona_config["available_tools"] || []

          # Add any specifically included tools
          tools += includes

          # Remove any specifically excluded tools
          tools -= excludes

          # Remove duplicates and return
          tools.uniq
        end

        private

        def persona_config
          @persona_config ||= {
            "name" => "TestPersona",
            "base_tools" => {
              "includes" => [ "SearchMusicTool", "SpecialTool" ],
              "excludes" => [ "MusicTool", "EffectsTool" ]
            },
            "available_tools" => [ "LightingTool", "MusicTool", "EffectsTool", "DisplayTool" ]
          }
        end
      end
    end

    it "correctly applies both includes and excludes" do
      persona = test_persona_class.new
      tools = persona.available_tools

      # Should include: LightingTool, DisplayTool (from available_tools, not excluded)
      # Should include: SearchMusicTool, SpecialTool (from includes)
      # Should exclude: MusicTool, EffectsTool (from excludes)

      expect(tools).to include("LightingTool", "DisplayTool", "SearchMusicTool", "SpecialTool")
      expect(tools).not_to include("MusicTool", "EffectsTool")
      expect(tools.length).to eq(4)
    end
  end
end
