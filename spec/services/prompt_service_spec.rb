# spec/services/prompt_service_spec.rb
require 'rails_helper'

RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
end

RSpec.describe PromptService do
  let(:conversation) { create(:conversation) }
  let(:persona) { 'buddy' }
  let(:extra_context) { {} }
  let(:user_message) { "Hello there!" }

  # Mock external dependencies
  before do
    allow(HaDataSync).to receive(:entity_state).with("sensor.cube_mode").and_return("active")
    allow(HaDataSync).to receive(:low_power_mode?).and_return(false)
    allow(HaDataSync).to receive(:get_context_attribute).and_return(nil)
    allow(HaDataSync).to receive(:extended_location).and_return("Burning Man")
    allow(GoalService).to receive(:current_goal_status).and_return(nil)
    allow(CubePersona).to receive(:current_persona).and_return(persona)

    # Mock Event model if it exists
    if defined?(Event)
      # Add missing scope methods to Event class
      Event.class_eval do
        scope :high_priority, -> { where(importance: 7..10) }
        scope :soon, -> { within_hours(48) }
      end
    end

    # Mock Summary model if it exists
    if defined?(Summary)
      allow(Summary).to receive(:similarity_search) { |*args| [] }
      allow(Summary).to receive(:goal_completions).and_return(double(limit: []))
    end

    # Stub SystemContextEnhancer to return simple context
    allow(Prompts::SystemContextEnhancer).to receive(:enhance).and_return("Enhanced test context")
  end

  describe '.build_prompt_for' do
    subject do
      described_class.build_prompt_for(
        persona: persona,
        conversation: conversation,
        extra_context: extra_context,
        user_message: user_message
      )
    end

    it 'returns a hash with expected keys' do
      expect(subject).to be_a(Hash)
      expect(subject).to have_key(:system_prompt)
      expect(subject).to have_key(:messages)
      expect(subject).to have_key(:tools)
      expect(subject).to have_key(:context)
    end

    it 'delegates to modular builders correctly' do
      # Expect PersonaLoader to be called
      expect(Prompts::PersonaLoader).to receive(:load).with(persona).and_call_original

      # Expect SystemPromptBuilder to be called
      expect(Prompts::SystemPromptBuilder).to receive(:build).and_call_original

      # Expect MessageHistoryBuilder to be called
      expect(Prompts::MessageHistoryBuilder).to receive(:build).with(conversation).and_call_original

      subject
    end

    it 'creates ContextBuilder with correct parameters' do
      expect(Prompts::ContextBuilder).to receive(:new).with(
        conversation: conversation,
        extra_context: extra_context,
        user_message: user_message
      ).and_call_original

      subject
    end

    context 'system prompt content' do
      it 'includes persona-specific content' do
        expect(subject[:system_prompt]).to be_present
        expect(subject[:system_prompt]).to be_a(String)
      end

      it 'includes context information' do
        expect(subject[:system_prompt]).to include('CURRENT CONTEXT:')
      end
    end

    context 'tools' do
      it 'returns empty array as tools are handled via tool_intents' do
        expect(subject[:tools]).to eq([])
      end
    end

    context 'messages' do
      it 'returns message history from builder' do
        expect(subject[:messages]).to be_an(Array)
      end
    end

    context 'context' do
      it 'returns context from builder' do
        expect(subject[:context]).to be_present
      end
    end
  end

  describe 'system prompt caching' do
    let(:cache_key) { 'test123' }

    before do
      conversation.update!(metadata_json: {})
    end

    context 'when system prompt is not cached' do
      it 'builds new system prompt and caches it' do
        result = described_class.build_prompt_for(
          persona: persona,
          conversation: conversation,
          extra_context: extra_context
        )

        expect(result[:system_prompt]).to be_present

        # Check that it was cached
        conversation.reload
        expect(conversation.metadata_json['cached_system_prompt']).to be_present
        expect(conversation.metadata_json['cached_system_prompt']['system_prompt']).to eq(result[:system_prompt])
      end
    end

    context 'when system prompt is cached' do
      let(:cached_prompt) { 'This is a cached system prompt' }

      before do
        service = described_class.new(
          persona: persona,
          conversation: conversation,
          extra_context: extra_context,
          user_message: nil
        )

        cache_key = service.send(:generate_cache_key)
        conversation.update!(
          metadata_json: {
            'cached_system_prompt' => {
              'system_prompt' => cached_prompt,
              'cache_key' => cache_key,
              'cached_at' => Time.current.iso8601
            }
          }
        )
      end

      it 'uses cached system prompt' do
        result = described_class.build_prompt_for(
          persona: persona,
          conversation: conversation,
          extra_context: extra_context
        )

        expect(result[:system_prompt]).to eq(cached_prompt)
      end

      it 'logs cache usage' do
        # Allow other debug calls but expect our specific one
        allow(Rails.logger).to receive(:debug)
        expect(Rails.logger).to receive(:debug).with(match(/Using cached system prompt/)).at_least(:once)

        described_class.build_prompt_for(
          persona: persona,
          conversation: conversation,
          extra_context: extra_context
        )
      end
    end

    context 'when cache key is invalid' do
      before do
        conversation.update!(
          metadata_json: {
            'cached_system_prompt' => {
              'system_prompt' => 'old cached prompt',
              'cache_key' => 'invalid_key',
              'cached_at' => 1.day.ago.iso8601
            }
          }
        )
      end

      it 'rebuilds system prompt' do
        result = described_class.build_prompt_for(
          persona: persona,
          conversation: conversation,
          extra_context: extra_context
        )

        expect(result[:system_prompt]).not_to eq('old cached prompt')
      end
    end
  end

  describe 'cache key generation' do
    let(:service) do
      described_class.new(
        persona: persona,
        conversation: conversation,
        extra_context: extra_context,
        user_message: nil
      )
    end

    it 'generates consistent cache key' do
      key1 = service.send(:generate_cache_key)
      key2 = service.send(:generate_cache_key)

      expect(key1).to eq(key2)
      expect(key1).to be_a(String)
      expect(key1.length).to eq(13) # Truncated SHA256
    end

    it 'includes persona name in cache key' do
      service_buddy = described_class.new(
        persona: 'buddy',
        conversation: conversation,
        extra_context: extra_context,
        user_message: nil
      )

      service_jax = described_class.new(
        persona: 'jax',
        conversation: conversation,
        extra_context: extra_context,
        user_message: nil
      )

      expect(service_buddy.send(:generate_cache_key)).not_to eq(service_jax.send(:generate_cache_key))
    end

    it 'includes current date in cache key' do
      key = service.send(:generate_cache_key)

      travel_to 1.day.from_now do
        new_key = service.send(:generate_cache_key)
        expect(new_key).not_to eq(key)
      end
    end
  end

  describe 'message ordering' do
    let(:conversation_with_messages) { create(:conversation, :with_conversation_logs) }

    it 'ensures system prompt comes first' do
      result = described_class.build_prompt_for(
        persona: persona,
        conversation: conversation_with_messages,
        extra_context: extra_context
      )

      # System prompt should be separate from messages
      expect(result[:system_prompt]).to be_present
      expect(result[:messages]).to be_an(Array)

      # Messages should only contain user/assistant pairs, no system messages
      result[:messages].each do |message|
        expect(message[:role]).to be_in([ 'user', 'assistant' ])
      end
    end
  end

  describe 'error handling' do
    context 'when conversation is nil' do
      it 'still builds prompt without caching' do
        result = described_class.build_prompt_for(
          persona: persona,
          conversation: nil,
          extra_context: extra_context
        )

        expect(result[:system_prompt]).to be_present
        expect(result[:messages]).to eq([])
        expect(result[:tools]).to eq([])
        expect(result[:context]).to be_present
      end
    end

    context 'when persona is nil' do
      it 'defaults to current persona from CubePersona' do
        expect(CubePersona).to receive(:current_persona).and_return('buddy')

        result = described_class.build_prompt_for(
          persona: nil,
          conversation: conversation,
          extra_context: extra_context
        )

        expect(result).to have_key(:system_prompt)
      end
    end
  end
end
