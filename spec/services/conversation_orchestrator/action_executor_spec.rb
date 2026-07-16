# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationOrchestrator::ActionExecutor do
  let(:session_id) { 'test_session_123' }
  let(:conversation_id) { 456 }
  let(:user_message) { 'Turn on the lights' }

  def call(llm_response)
    described_class.call(
      llm_response: llm_response,
      session_id: session_id,
      conversation_id: conversation_id,
      user_message: user_message
    )
  end

  describe '.call' do
    context 'with both a sound channel and other channels' do
      let(:llm_response) do
        {
          "speech" => "here you go",
          "lights" => "body deep purple, slow breathing",
          "marquee" => "HELLO in pink",
          "sound" => "play heavy metal and crank it"
        }
      end

      it 'sends the sound channel to the sound agent on its own lane' do
        expect(EnvironmentDirectorJob).to receive(:perform_later).with(
          hash_including(
            instruction: "play heavy metal and crank it",
            agent_id: Rails.configuration.hass_sound_agent,
            convo_prefix: "cube_sound",
            session_id: session_id,
            conversation_id: conversation_id,
            user_message: user_message
          )
        )
        allow(EnvironmentDirectorJob).to receive(:perform_later).with(hash_including(convo_prefix: "cube_env"))

        expect(call(llm_response).data[:dispatched_environment]).to be true
      end

      it 'sends the remaining channels to the main action agent as one labeled instruction' do
        allow(EnvironmentDirectorJob).to receive(:perform_later).with(hash_including(convo_prefix: "cube_sound"))
        expect(EnvironmentDirectorJob).to receive(:perform_later).with(
          hash_including(
            instruction: "lights: body deep purple, slow breathing\nmarquee: HELLO in pink",
            agent_id: Rails.configuration.hass_action_agent,
            convo_prefix: "cube_env"
          )
        )

        expect(call(llm_response).success?).to be true
      end
    end

    context 'with only non-sound channels' do
      let(:llm_response) { { "lights" => "everything dancing blue" } }

      it 'dispatches once, to the main agent only' do
        expect(EnvironmentDirectorJob).to receive(:perform_later).once.with(
          hash_including(instruction: "lights: everything dancing blue", convo_prefix: "cube_env")
        )

        expect(call(llm_response).data[:dispatched_environment]).to be true
      end
    end

    context 'with an unexpected extra channel key' do
      let(:llm_response) { { "confetti" => "shoot confetti" } }

      it 'still routes it to the main agent (nothing is silently dropped)' do
        expect(EnvironmentDirectorJob).to receive(:perform_later).once.with(
          hash_including(instruction: "confetti: shoot confetti", convo_prefix: "cube_env")
        )

        expect(call(llm_response).data[:dispatched_environment]).to be true
      end
    end

    context 'with no action channels (talk-only turn)' do
      let(:llm_response) { { "speech" => "just talking", "continue_conversation" => true } }

      it 'does not dispatch and returns dispatched_environment: false' do
        expect(EnvironmentDirectorJob).not_to receive(:perform_later)

        result = call(llm_response)
        expect(result.success?).to be true
        expect(result.data[:dispatched_environment]).to be false
      end
    end

    context 'with empty LLM response' do
      it 'returns success with empty results and no dispatch' do
        expect(EnvironmentDirectorJob).not_to receive(:perform_later)

        result = call({})
        expect(result.success?).to be true
        expect(result.data[:sync_results]).to eq({})
        expect(result.data[:dispatched_environment]).to be false
      end
    end
  end
end
