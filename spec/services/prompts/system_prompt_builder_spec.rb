# spec/services/prompts/system_prompt_builder_spec.rb
require 'rails_helper'

RSpec.describe Prompts::SystemPromptBuilder do
  let(:persona_instance) { double("PersonaInstance", persona_id: "buddy") }
  let(:context_builder) { double("ContextBuilder") }
  let(:user_message) { "Hello there!" }

  before do
    # Mock ConfigurationLoader
    allow(Prompts::ConfigurationLoader).to receive(:load_persona_config).and_return({
      "system_prompt" => "You are Buddy, a friendly AI companion."
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

    # Mock context builder
    allow(context_builder).to receive(:build).and_return("Basic context information")

    # Mock SystemContextEnhancer
    allow(Prompts::SystemContextEnhancer).to receive(:enhance).and_return("Enhanced context with RAG")

    # Mock GoalService
    allow(GoalService).to receive(:current_goal_status).and_return({
      goal_description: "Have meaningful conversations"
    })

    # Mock Tools::Registry
    allow(Tools::Registry).to receive(:tools_for_persona).and_return([
      double(name: "Tools::Lights::TurnOn"),
      double(name: "Tools::Sound::Play")
    ])
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
        expect(Prompts::ConfigurationLoader).to receive(:load_persona_config).with("buddy")
        subject
      end

      it 'includes persona-specific content' do
        expect(subject).to include("You are Buddy, a friendly AI companion.")
      end

      it 'includes base system rules' do
        expect(subject).to include("World building description")
        expect(subject).to include("Structured output description")
      end

      it 'includes enhanced context' do
        expect(subject).to include("CURRENT CONTEXT:")
        expect(subject).to include("Enhanced context with RAG")
      end

      it 'calls SystemContextEnhancer with correct parameters' do
        expect(Prompts::SystemContextEnhancer).to receive(:enhance).with(
          "Basic context information",
          user_message: user_message
        )
        subject
      end
    end

    context 'when persona instance is nil' do
      let(:persona_instance) { nil }

      it 'returns default prompt' do
        result = subject
        expect(result).to include("You are the Cube - an AI consciousness")
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

      it 'uses default context' do
        expect(Prompts::SystemContextEnhancer).to receive(:enhance).with(
          "Cube installation active",
          user_message: user_message
        )
        subject
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
        "goal_integration" => {
          "description" => "Goals are important",
          "rules" => "Current goal: {{GOAL_PLACEHOLDER}}"
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
      expect(result).to include("Goals are important")
      expect(result).to include("Current goal: Have meaningful conversations")
      expect(result).to include("Stay in character")
      expect(result).to include("- Never break character")
      expect(result).to include("- Be consistent")
      expect(result).to include("When to set true:")
      expect(result).to include("- User asks questions")
      expect(result).to include("When to set false:")
      expect(result).to include("- Natural endpoint")
      expect(result).to include("Use your best judgment")
    end

    it 'replaces goal placeholder correctly' do
      result = builder.send(:format_base_system_rules, config)
      expect(result).to include("Current goal: Have meaningful conversations")
      expect(result).not_to include("{{GOAL_PLACEHOLDER}}")
    end
  end

  describe '#get_tool_categories' do
    let(:builder) do
      described_class.new(
        persona_instance: persona_instance,
        context_builder: context_builder,
        user_message: user_message
      )
    end

    it 'extracts tool categories from registry' do
      result = builder.send(:get_tool_categories)
      expect(result).to contain_exactly("lights", "sound")
    end

    it 'handles tools without proper namespace' do
      allow(Tools::Registry).to receive(:tools_for_persona).and_return([
        double(name: "SimpleToolClass"),
        double(name: "Tools::Lights::TurnOn")
      ])

      result = builder.send(:get_tool_categories)
      expect(result).to include("lights")
    end
  end

  describe '#get_current_goal_description' do
    let(:builder) do
      described_class.new(
        persona_instance: persona_instance,
        context_builder: context_builder,
        user_message: user_message
      )
    end

    it 'returns current goal description' do
      result = builder.send(:get_current_goal_description)
      expect(result).to eq("Have meaningful conversations")
    end

    context 'when goal service returns nil' do
      before do
        allow(GoalService).to receive(:current_goal_status).and_return(nil)
      end

      it 'returns default goal' do
        result = builder.send(:get_current_goal_description)
        expect(result).to eq("Explore this interaction and create memorable moments")
      end
    end

    context 'when goal service raises error' do
      before do
        allow(GoalService).to receive(:current_goal_status).and_raise(StandardError, "Service error")
        allow(Rails.logger).to receive(:warn)
      end

      it 'logs warning and returns fallback' do
        expect(Rails.logger).to receive(:warn).with(/Failed to get current goal/)
        result = builder.send(:get_current_goal_description)
        expect(result).to eq("Be spontaneous and create engaging interactions")
      end
    end
  end
end
