# spec/services/prompts/system_prompt_builder_spec.rb
require 'rails_helper'

RSpec.describe Prompts::SystemPromptBuilder do
  let(:persona_instance) { double("PersonaInstance", persona_id: "buddy") }
  let(:context_builder) { double("ContextBuilder") }
  let(:user_message) { "Hello there!" }

  before do
    allow(Prompts::ConfigurationLoader).to receive(:base_system_prompt)
      .and_return("# WHAT YOU ARE\n\nYou are the GlitchCube.")
    allow(Prompts::ConfigurationLoader).to receive(:end_system_prompt)
      .and_return("# RESPONSE FORMAT\n\nReturn JSON: speech, inner_monologue, actions, continue_conversation.")
    allow(Prompts::ConfigurationLoader).to receive(:load_persona_config).and_return({
      "persona_prompt" => "You are Buddy, an enthusiastic helper cube."
    })

    allow(context_builder).to receive(:build).and_return("Time: 7:53 PM on Friday") if context_builder
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
      it 'loads the persona config by persona_id' do
        expect(Prompts::ConfigurationLoader).to receive(:load_persona_config).with("buddy")
        subject
      end

      it 'includes the base system prompt, persona sheet, context, and end instructions' do
        expect(subject).to include("# WHAT YOU ARE")
        expect(subject).to include("You are Buddy, an enthusiastic helper cube.")
        expect(subject).to include("# CURRENT CONTEXT")
        expect(subject).to include("Time: 7:53 PM on Friday")
        expect(subject).to include("# RESPONSE FORMAT")
      end

      it 'orders the pieces base -> persona -> context -> end' do
        base_idx    = subject.index("# WHAT YOU ARE")
        persona_idx = subject.index("You are Buddy")
        context_idx = subject.index("# CURRENT CONTEXT")
        end_idx     = subject.index("# RESPONSE FORMAT")

        expect(base_idx).to be < persona_idx
        expect(persona_idx).to be < context_idx
        expect(context_idx).to be < end_idx
      end

      it 'carries no stateful self-model or memory sections' do
        expect(subject).not_to include("WHO YOU CURRENTLY ARE:")
        expect(subject).not_to include("WHAT YOUR BODY CAN DO:")
        expect(subject).not_to include("THINGS YOU REMEMBER")
      end
    end

    context 'tools section injection' do
      before do
        allow(Prompts::ConfigurationLoader).to receive(:base_system_prompt)
          .and_return("# YOUR TOOLS\n\n{{TOOLS}}\n\n# YOUR PERSONA")
      end

      it 'fills the {{TOOLS}} placeholder with the shared tools description' do
        allow(Prompts::ConfigurationLoader).to receive(:tools_prompt).and_return("- lights — your LEDs\n- sound — play music")

        expect(subject).to include("- lights — your LEDs")
        expect(subject).to include("- sound — play music")
        expect(subject).not_to include("{{TOOLS}}")
      end

      it 'shows a fallback line when there is no tools description' do
        allow(Prompts::ConfigurationLoader).to receive(:tools_prompt).and_return(nil)
        expect(subject).to include("no special tools")
      end
    end

    context 'when the persona config has no persona_prompt' do
      before do
        allow(Prompts::ConfigurationLoader).to receive(:load_persona_config).and_return(nil)
        allow(Rails.logger).to receive(:warn)
      end

      it 'logs a warning and falls back to a default persona line' do
        expect(Rails.logger).to receive(:warn).with(/No persona_prompt/)
        expect(subject).to include("fractured personality")
      end
    end

    context 'when context builder is nil' do
      let(:context_builder) { nil }

      it 'omits the CURRENT CONTEXT section' do
        expect(subject).not_to include("# CURRENT CONTEXT")
        expect(subject).to include("# WHAT YOU ARE")
        expect(subject).to include("# RESPONSE FORMAT")
      end
    end
  end
end
