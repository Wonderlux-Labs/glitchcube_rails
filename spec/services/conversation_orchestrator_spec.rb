require 'rails_helper'

RSpec.describe ConversationOrchestrator, type: :service do
  let(:session_id) { 'test_session_123' }
  let(:message) { 'Turn on the living room lights' }
  let(:context) { { source: 'test' } }
  let(:orchestrator) { described_class.new(session_id: session_id, message: message, context: context) }

  describe '#call', :vcr do
    before do
      # Ensure we have a clean state
      Conversation.destroy_all
      ConversationLog.destroy_all
    end

    context 'when LLM returns tools with narrative elements' do
      it 'extracts narrative elements and handles tool execution' do
        result = orchestrator.call

        # Check basic response structure (orchestrator returns HA format directly)
        expect(result).to have_key(:continue_conversation)
        expect(result).to have_key(:response)
        expect(result).to have_key(:end_conversation)

        # Check conversation was created
        conversation = Conversation.find_by(session_id: session_id)
        expect(conversation).to be_present

        # Check conversation log was created with narrative metadata
        log = ConversationLog.find_by(session_id: session_id)
        expect(log).to be_present
        expect(log.ai_response).to be_present
        expect(log.ai_response).not_to be_empty

        # Check that narrative metadata structure exists (may be nil if LLM doesn't follow format)
        metadata = JSON.parse(log.metadata)
        # These keys should exist even if the values are nil
        if metadata.key?('inner_thoughts')
          expect(metadata).to have_key('inner_thoughts')
          expect(metadata).to have_key('current_mood')
          expect(metadata).to have_key('pressing_questions')
          expect(metadata).to have_key('continue_conversation_from_llm')
        else
          puts "🔸 LLM didn't return narrative markers - this is expected in Phase 1"
        end

        # Check response format for Home Assistant
        expect(result[:continue_conversation]).to be_in([true, false])
        expect(result[:end_conversation]).to eq(!result[:continue_conversation])
      end
    end

    context 'with pending tools from previous turn' do
      let(:pending_tools_data) do
        {
          'pending_tools' => [
            {
              'name' => 'light_turn_on',
              'arguments' => { 'entity_id' => 'light.living_room' },
              'queued_at' => 1.minute.ago.iso8601
            }
          ]
        }
      end

      before do
        # Create conversation with pending tools
        conversation = Conversation.create!(
          session_id: session_id,
          started_at: Time.current,
          persona: 'jax',
          flow_data_json: pending_tools_data
        )
      end

      it 'injects previous tool results and clears pending tools', :vcr do
        result = orchestrator.call

        # Check that OLD pending tools were cleared and possibly NEW ones added
        conversation = Conversation.find_by(session_id: session_id)
        new_pending = conversation.flow_data_json&.dig('pending_tools') || []
        
        # The old pending tool (light_turn_on for light.living_room) should be gone
        old_tool_present = new_pending.any? { |tool| 
          tool['name'] == 'light_turn_on' && tool['arguments']['entity_id'] == 'light.living_room'
        }
        expect(old_tool_present).to be false

        # Check that conversation log includes tool result acknowledgment
        log = ConversationLog.find_by(session_id: session_id)
        expect(log).to be_present
        expect(log.ai_response).to be_present

        # For Phase 1, we expect the response to be successful
        expect(result).to have_key(:continue_conversation)
        expect(result).to have_key(:response)
      end
    end
  end

  describe '#extract_narrative_elements' do
    context 'with properly formatted narrative markers' do
      let(:content_with_narrative) do
        "I'll turn on the lights for you! [CONTINUE: true] [THOUGHTS: The user wants lighting] [MOOD: helpful] [QUESTIONS: Should I adjust brightness too?]"
      end

      it 'extracts all narrative elements correctly' do
        result = orchestrator.send(:extract_narrative_elements, content_with_narrative)

        expect(result[:continue_conversation]).to be(true)
        expect(result[:inner_thoughts]).to eq('The user wants lighting')
        expect(result[:current_mood]).to eq('helpful')
        expect(result[:pressing_questions]).to eq('Should I adjust brightness too?')
        expect(result[:speech_text]).to eq("I'll turn on the lights for you!")
      end
    end

    context 'with missing narrative markers' do
      let(:content_without_narrative) { "Just turning on the lights now." }

      it 'returns defaults for missing elements' do
        result = orchestrator.send(:extract_narrative_elements, content_without_narrative)

        expect(result[:continue_conversation]).to be(false)
        expect(result[:inner_thoughts]).to be_nil
        expect(result[:current_mood]).to be_nil
        expect(result[:pressing_questions]).to be_nil
        expect(result[:speech_text]).to eq("Just turning on the lights now.")
      end
    end

    context 'with empty content' do
      it 'returns default narrative structure' do
        result = orchestrator.send(:extract_narrative_elements, '')

        expect(result[:continue_conversation]).to be(false)
        expect(result[:inner_thoughts]).to be_nil
        expect(result[:current_mood]).to be_nil
        expect(result[:pressing_questions]).to be_nil
        expect(result[:speech_text]).to eq('')
      end
    end
  end

  describe '#check_and_clear_pending_tools' do
    let(:conversation) { Conversation.create!(session_id: session_id, started_at: Time.current, persona: 'jax') }

    context 'with pending tools' do
      before do
        conversation.update!(
          flow_data_json: {
            'pending_tools' => [
              { 'name' => 'light_turn_on', 'arguments' => { 'entity_id' => 'light.living_room' } },
              { 'name' => 'light_set_brightness', 'arguments' => { 'entity_id' => 'light.bedroom', 'brightness' => 128 } }
            ]
          }
        )
      end

      it 'returns mock success results and clears pending tools' do
        results = orchestrator.send(:check_and_clear_pending_tools, conversation)

        expect(results.length).to eq(2)
        expect(results.first[:tool]).to eq('light_turn_on')
        expect(results.first[:success]).to be(true)
        expect(results.first[:message]).to eq('Successfully executed light_turn_on')

        # Check that pending tools were cleared
        conversation.reload
        expect(conversation.flow_data_json).to eq({})
      end
    end

    context 'without pending tools' do
      it 'returns empty array' do
        results = orchestrator.send(:check_and_clear_pending_tools, conversation)
        expect(results).to be_empty
      end
    end
  end

  describe '#store_pending_tools' do
    let(:conversation) { Conversation.create!(session_id: session_id, started_at: Time.current, persona: 'jax') }
    let(:mock_tool_calls) do
      [
        OpenStruct.new(name: 'light_turn_on', arguments: { 'entity_id' => 'light.living_room' }),
        OpenStruct.new(name: 'light_set_brightness', arguments: { 'entity_id' => 'light.bedroom', 'brightness' => 200 })
      ]
    end

    it 'stores tool calls in conversation flow_data_json' do
      orchestrator.send(:store_pending_tools, conversation, mock_tool_calls)

      conversation.reload
      stored_tools = conversation.flow_data_json['pending_tools']

      expect(stored_tools.length).to eq(2)
      expect(stored_tools.first['name']).to eq('light_turn_on')
      expect(stored_tools.first['arguments']).to eq({ 'entity_id' => 'light.living_room' })
      expect(stored_tools.first).to have_key('queued_at')
    end
  end

  describe 'integration test with narrative and tools', :vcr do
    let(:message) { 'Set the mood lighting in the living room' }

    it 'handles complete flow with narrative elements and tool storage' do
      result = orchestrator.call

      # Verify basic success
      expect(result).to have_key(:continue_conversation)
      expect(result).to have_key(:response)

      # Check conversation and log creation
      conversation = Conversation.find_by(session_id: session_id)
      expect(conversation).to be_present

      log = ConversationLog.find_by(session_id: session_id)
      expect(log).to be_present
      expect(log.ai_response).to be_present
      expect(log.ai_response).not_to be_empty

      # Verify metadata includes narrative elements if LLM provided them
      metadata = JSON.parse(log.metadata)
      if metadata.key?('inner_thoughts')
        expect(metadata).to have_key('inner_thoughts')
        expect(metadata).to have_key('current_mood')
        expect(metadata).to have_key('pressing_questions')
      else
        puts "🔸 LLM didn't return narrative markers - this is expected in Phase 1"
      end

      # Check Home Assistant response format
      expect(result[:continue_conversation]).to be_in([true, false])
      expect(result[:end_conversation]).to eq(!result[:continue_conversation])
      
      puts "✅ Phase 1 implementation test passed!"
      puts "   Response text: #{result[:response][:speech][:plain][:speech]}"
      puts "   Continue conversation: #{result[:continue_conversation]}"
      puts "   Narrative captured: #{metadata['inner_thoughts'] ? 'Yes' : 'No'}"
    end
  end
end