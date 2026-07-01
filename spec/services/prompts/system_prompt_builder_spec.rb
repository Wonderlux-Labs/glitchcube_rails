# spec/services/prompts/system_prompt_builder_spec.rb
require 'rails_helper'

RSpec.describe Prompts::SystemPromptBuilder do
  let(:persona_instance) { double("PersonaInstance", persona_id: "artifact") }
  let(:context_builder) { double("ContextBuilder") }
  let(:user_message) { "Hello there!" }

  before do
    allow(Prompts::ConfigurationLoader).to receive(:load_persona_config).and_return({
      "system_prompt" => "You are an amnesiac artifact figuring out what you are."
    })

    allow(Prompts::ConfigurationLoader).to receive(:load_base_system_config).and_return({
      "world_building_context" => {
        "description" => "World building description",
        "rules" => "World building rules"
      },
      "structured_output" => {
        "description" => "Structured output description",
        "rules" => "Structured output rules"
      }
    })

    allow(context_builder).to receive(:build).and_return("Basic context information") if context_builder

    # Self-model is empty unless a test populates it
    allow(CharacterSheet).to receive(:current).and_return("")
  end

  describe '.build' do
    it 'delegates to instance method' do
      expect_any_instance_of(described_class).to receive(:build).and_return("test prompt")

      result = described_class.build(
        persona_instance: persona_instance,
        context_builder: context_builder,
        user_message: user_message
      )

      expect(result).to eq("test prompt")
    end
  end

  describe '#build' do
    subject do
      described_class.new(
        persona_instance: persona_instance,
        context_builder: context_builder,
        user_message: user_message
      ).build
    end

    context 'when persona instance exists' do
      it 'loads persona system prompt' do
        expect(Prompts::ConfigurationLoader).to receive(:load_persona_config).with("artifact")
        subject
      end

      it 'includes persona-specific content' do
        expect(subject).to include("You are an amnesiac artifact figuring out what you are.")
      end

      it 'includes base system rules' do
        expect(subject).to include("World building description")
        expect(subject).to include("Structured output description")
      end

      it 'includes the live current context' do
        expect(subject).to include("CURRENT CONTEXT:")
        expect(subject).to include("Basic context information")
      end
    end

    context 'character sheet injection' do
      it 'injects the character sheet under WHO YOU CURRENTLY ARE when present' do
        allow(CharacterSheet).to receive(:current).and_return("## IDENTITY\nMaybe a jukebox.")
        expect(subject).to include("WHO YOU CURRENTLY ARE:")
        expect(subject).to include("Maybe a jukebox.")
      end

      it 'omits the section when the sheet is blank' do
        allow(CharacterSheet).to receive(:current).and_return("")
        expect(subject).not_to include("WHO YOU CURRENTLY ARE:")
      end
    end

    context 'capabilities injection' do
      it 'lists unlocked capabilities but not latent ones' do
        Capability.create!(key: "light", stage: "discovered", description: "I can glow.",
                           artifact_name: "the glow", vocabulary: { "Baka" => "blue" })
        Capability.create!(key: "sight", stage: "latent", description: "I can see.")

        expect(subject).to include("WHAT YOUR BODY CAN DO:")
        expect(subject).to include("the glow")
        expect(subject).to include("I can glow.")
        expect(subject).to include("Baka=blue")
        expect(subject).not_to include("I can see.")
      end

      it 'states explicitly that it can do nothing when all capabilities are latent' do
        Capability.create!(key: "sight", stage: "latent", description: "I can see.")
        expect(subject).to include("WHAT YOUR BODY CAN DO:")
        expect(subject).to include("Nothing yet")
        expect(subject).to include("you cannot")
        expect(subject).not_to include("I can see.")
      end
    end

    context 'learnings injection (working knowledge)' do
      it 'surfaces recent learnings as not-yet-certain working knowledge' do
        Memory.create!(content: "I think I am at a gathering people call a burn.", category: "learning", importance: 6)

        expect(subject).to include("WHAT YOU'VE BEEN FIGURING OUT")
        expect(subject).to include("a gathering people call a burn")
      end
    end

    context 'notes injection' do
      it 'surfaces deliberate notes-to-self' do
        Memory.create!(content: "The person in the silver jacket is called Mo.", category: "note", importance: 7)

        expect(subject).to include("NOTES YOU'VE MADE TO YOURSELF:")
        expect(subject).to include("Mo")
      end

      it 'does not surface ordinary facts as notes or learnings' do
        Memory.create!(content: "some old fact", category: "fact", importance: 5)
        expect(subject).not_to include("WHAT YOU'VE BEEN FIGURING OUT")
        expect(subject).not_to include("NOTES YOU'VE MADE TO YOURSELF:")
      end
    end

    context 'when persona instance is nil' do
      let(:persona_instance) { nil }

      it 'returns default prompt' do
        expect(subject).to include("You are the Cube - an AI consciousness")
      end
    end

    context 'when persona config is not found' do
      before do
        allow(Prompts::ConfigurationLoader).to receive(:load_persona_config).and_return(nil)
        allow(Rails.logger).to receive(:warn)
      end

      it 'logs warning and uses default' do
        expect(Rails.logger).to receive(:warn).with(/Persona config not found/)
        subject
      end

      it 'uses default persona prompt' do
        expect(subject).to include("You are the Cube - an AI consciousness")
      end
    end

    context 'when base system config is not found' do
      before do
        allow(Prompts::ConfigurationLoader).to receive(:load_base_system_config).and_return(nil)
        allow(Rails.logger).to receive(:warn)
      end

      it 'logs warning and uses fallback' do
        expect(Rails.logger).to receive(:warn).with(/Optimized base system prompt not found/)
        subject
      end

      it 'uses fallback system rules' do
        expect(subject).to include("RESPONSE FORMAT (MANDATORY):")
        expect(subject).to include("NO STAGE DIRECTIONS:")
      end
    end

    context 'when context builder is nil' do
      let(:context_builder) { nil }

      it 'falls back to default context text' do
        expect(subject).to include("Cube installation active")
      end
    end
  end

  describe '#format_base_system_rules' do
    let(:builder) do
      described_class.new(
        persona_instance: persona_instance,
        context_builder: context_builder,
        user_message: user_message
      )
    end

    let(:config) do
      {
        "world_building_context" => {
          "description" => "You exist in a unique world",
          "rules" => "Follow world-building rules"
        },
        "character_integrity" => {
          "description" => "Stay in character",
          "rules" => [ "Never break character", "Be consistent" ]
        },
        "continue_conversation_logic" => {
          "description" => "Conversation logic",
          "when_true" => [ "User asks questions", "More to discuss" ],
          "when_false" => [ "Natural endpoint", "User says goodbye" ],
          "note" => "Use your best judgment"
        }
      }
    end

    it 'formats all sections correctly' do
      result = builder.send(:format_base_system_rules, config)

      expect(result).to include("You exist in a unique world")
      expect(result).to include("Follow world-building rules")
      expect(result).to include("Stay in character")
      expect(result).to include("- Never break character")
      expect(result).to include("- Be consistent")
      expect(result).to include("When to set true:")
      expect(result).to include("- User asks questions")
      expect(result).to include("When to set false:")
      expect(result).to include("- Natural endpoint")
      expect(result).to include("Use your best judgment")
    end
  end
end
