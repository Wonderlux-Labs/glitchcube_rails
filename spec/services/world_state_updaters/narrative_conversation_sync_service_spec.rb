# spec/services/world_state_updaters/narrative_conversation_sync_service_spec.rb

require 'rails_helper'

RSpec.describe WorldStateUpdaters::NarrativeConversationSyncService do
  let(:service) { described_class.new }
  let(:ha_service) { instance_double(HomeAssistantService) }

  before do
    allow(HomeAssistantService).to receive(:new).and_return(ha_service)
    allow(ha_service).to receive(:set_entity_state)
  end

  describe '.sync_latest_conversation' do
    context 'when conversation logs exist' do
      let!(:conversation_log) do
        # ConversationLog no longer has a persona column; the service now reads
        # persona from metadata (persona/current_persona/active_persona).
        create(:conversation_log,
               conversation: create(:conversation, session_id: 'test-session-123', persona: 'buddy'),
               user_message: 'Hello Buddy!',
               ai_response: 'Holy shit, hi there! How can I fucking help you?',
               metadata: {
                 persona: 'buddy',
                 inner_thoughts: 'A new customer! I need to help them!',
                 current_mood: 'excited',
                 continue_conversation: true,
                 environment_instruction: 'Make lights bright yellow'
               }.to_json)
      end

      it 'syncs the latest conversation to world_info sensor' do
        expect(ha_service).to receive(:set_entity_state) do |entity_id, state, attributes|
          expect(entity_id).to eq('sensor.world_info')
          expect(state).to eq('narrative_updated')
          expect(attributes[:last_conversation][:persona]).to eq('buddy')
          expect(attributes[:narrative_metadata][:inner_monologue]).to eq('A new customer! I need to help them!')
          expect(attributes[:narrative_metadata][:actions]).to eq('Make lights bright yellow')
        end

        described_class.sync_latest_conversation
      end
    end

    context 'when no conversation logs exist' do
      it 'logs a warning and returns nil' do
        expect(Rails.logger).to receive(:warn).with(/No conversation logs found/)
        result = described_class.sync_latest_conversation
        expect(result).to be_nil
      end
    end
  end

  describe '#sync_conversation' do
    let(:conversation_log) do
      # ConversationLog no longer has a persona column; persona is read from metadata.
      create(:conversation_log,
             conversation: create(:conversation, session_id: 'test-session-456', persona: 'jax'),
             user_message: 'Play some music',
             ai_response: 'What kind of music? None of that electronic bullshit!',
             metadata: {
               persona: 'jax',
               inner_monologue: 'Another philistine asking for garbage',
               continue_conversation: true,
               actions: 'play some Led Zeppelin'
             }.to_json,
             tool_results: { music_tool: { success: true, track: 'Led Zeppelin - Stairway to Heaven' } }.to_json)
    end

    it 'extracts and syncs narrative data correctly' do
      expect(ha_service).to receive(:set_entity_state) do |entity_id, state, attributes|
        expect(entity_id).to eq('sensor.world_info')
        expect(state).to eq('narrative_updated')

        # Check last conversation data
        expect(attributes[:last_conversation][:persona]).to eq('jax')
        expect(attributes[:last_conversation][:ai_response]).to include('electronic bullshit')

        # Check narrative metadata
        expect(attributes[:narrative_metadata][:inner_monologue]).to eq('Another philistine asking for garbage')
        expect(attributes[:narrative_metadata][:actions]).to eq('play some Led Zeppelin')
        expect(attributes[:narrative_metadata][:continue_conversation]).to be(true)

        # Check tool results (parsed from JSON, so string keys)
        expect(attributes[:tool_results]['music_tool']['track']).to eq('Led Zeppelin - Stairway to Heaven')

        # Check interaction context
        expect(attributes[:interaction_context][:total_messages]).to eq(1)
      end

      service.sync_conversation(conversation_log)
    end

    it 'handles malformed metadata gracefully' do
      conversation_log.update!(metadata: 'invalid json')

      expect(ha_service).to receive(:set_entity_state) do |entity_id, state, attributes|
        expect(attributes[:narrative_metadata][:inner_monologue]).to be_nil
        expect(attributes[:narrative_metadata][:actions]).to be_nil
      end

      service.sync_conversation(conversation_log)
    end

    it 'sanitizes sensitive information' do
      conversation_log.update!(
        user_message: 'My SSN is 123-45-6789 and credit card is 1234567890123456',
        ai_response: 'I got your SSN 123-45-6789!'
      )

      expect(ha_service).to receive(:set_entity_state) do |entity_id, state, attributes|
        expect(attributes[:last_conversation][:user_message]).to include('[REDACTED]')
        expect(attributes[:last_conversation][:ai_response]).to include('[REDACTED]')
        expect(attributes[:last_conversation][:user_message]).not_to include('123-45-6789')
      end

      service.sync_conversation(conversation_log)
    end
  end
end
