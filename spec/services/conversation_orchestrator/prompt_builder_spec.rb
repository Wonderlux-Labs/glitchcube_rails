# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationOrchestrator::PromptBuilder do
  let(:conversation) { instance_double(Conversation, id: 123, metadata_json: nil) }
  let(:persona) { instance_double(CubePersona, name: "Assistant") }
  let(:user_message) { "Turn on the lights" }
  let(:context) { { user_id: "user123", source: "home_assistant" } }

  let(:mock_prompt_data) do
    {
      messages: [
        { role: "system", content: "You are a helpful assistant" },
        { role: "user", content: user_message }
      ],
      system_prompt: "You are a helpful assistant"
    }
  end

  describe '.call' do
    context 'with valid parameters' do
      before do
        allow(PromptService).to receive(:build_prompt_for)
          .with(
            persona: persona,
            conversation: conversation,
            extra_context: context,
            user_message: user_message
          )
          .and_return(mock_prompt_data)
      end

      it 'builds prompt successfully using PromptService' do
        result = described_class.call(
          conversation: conversation,
          persona: persona,
          user_message: user_message,
          context: context
        )

        expect(result.success?).to be true
        expect(result.data).to eq(mock_prompt_data)
        expect(PromptService).to have_received(:build_prompt_for)
      end
    end

    context 'with pending HA results in conversation metadata' do
      let(:metadata_with_results) do
        {
          "pending_ha_results" => [
            {
              "id" => "result_1",
              "instruction" => "turn on lights",
              "ha_response" => {
                "response" => {
                  "data" => {
                    "success" => [ { "name" => "Living Room Light" } ],
                    "failed" => []
                  }
                }
              },
              "timestamp" => 1.minute.ago.to_f,
              "processed" => false
            }
          ]
        }
      end

      before do
        allow(conversation).to receive(:metadata_json).and_return(metadata_with_results)
        allow(conversation).to receive(:update!)
        allow(PromptService).to receive(:build_prompt_for).and_return(mock_prompt_data.dup)
      end

      it 'injects HA results into the prompt and clears them' do
        result = described_class.call(
          conversation: conversation,
          persona: persona,
          user_message: user_message,
          context: context
        )

        expect(result.success?).to be true

        # Should have injected the HA result as a system message
        messages = result.data[:messages]
        injected_message = messages.find { |msg| msg[:role] == "system" && msg[:content].include?("turn on lights") }
        expect(injected_message).to be_present

        # Should have marked the results as processed
        expect(conversation).to have_received(:update!).with(
          metadata_json: hash_including(
            "pending_ha_results" => array_including(
              hash_including("processed" => true)
            )
          )
        )
      end
    end

    context 'with stale HA results (older than 5 minutes)' do
      let(:metadata_with_stale_results) do
        {
          "pending_ha_results" => [
            {
              "id" => "stale_result",
              "tool" => "old.tool",
              "result" => { "success" => true },
              "timestamp" => 10.minutes.ago.to_f,
              "processed" => false
            }
          ]
        }
      end

      before do
        allow(conversation).to receive(:metadata_json).and_return(metadata_with_stale_results)
        allow(conversation).to receive(:update!)
        allow(PromptService).to receive(:build_prompt_for).and_return(mock_prompt_data.dup)
      end

      it 'ignores stale results and clears them' do
        result = described_class.call(
          conversation: conversation,
          persona: persona,
          user_message: user_message,
          context: context
        )

        expect(result.success?).to be true

        # Should not have injected stale results
        messages = result.data[:messages]
        injected_message = messages.find { |msg| msg[:role] == "system" && msg[:content].include?("old.tool") }
        expect(injected_message).to be_nil

        # Should have marked the stale results as processed
        expect(conversation).to have_received(:update!).with(
          metadata_json: hash_including(
            "pending_ha_results" => array_including(
              hash_including("processed" => true)
            )
          )
        )
      end
    end

    context 'when PromptService raises an error' do
      before do
        allow(PromptService).to receive(:build_prompt_for)
          .and_raise(StandardError.new("Prompt service failed"))
      end

      it 'returns a failure result' do
        result = described_class.call(
          conversation: conversation,
          persona: persona,
          user_message: user_message,
          context: context
        )

        expect(result.success?).to be false
        expect(result.error).to include("Prompt building failed")
      end
    end

    context 'when conversation has no metadata' do
      before do
        allow(conversation).to receive(:metadata_json).and_return(nil)
        allow(PromptService).to receive(:build_prompt_for).and_return(mock_prompt_data)
      end

      it 'proceeds normally without trying to inject HA results' do
        result = described_class.call(
          conversation: conversation,
          persona: persona,
          user_message: user_message,
          context: context
        )

        expect(result.success?).to be true
        expect(result.data).to eq(mock_prompt_data)
      end
    end

    context 'when conversation has empty pending_ha_results' do
      let(:empty_metadata) { { "pending_ha_results" => [] } }

      before do
        allow(conversation).to receive(:metadata_json).and_return(empty_metadata)
        allow(PromptService).to receive(:build_prompt_for).and_return(mock_prompt_data)
      end

      it 'proceeds normally without injection' do
        result = described_class.call(
          conversation: conversation,
          persona: persona,
          user_message: user_message,
          context: context
        )

        expect(result.success?).to be true
        expect(result.data).to eq(mock_prompt_data)
      end
    end

    # Both action lanes (the sound/jukebox agent AND the main action agent) append
    # their replies to the SAME pending_ha_results queue (see EnvironmentDirectorJob).
    # This exercises the real cross-turn contract with a persisted Conversation:
    #   1. the NEXT turn folds in BOTH agents' results, exactly once each;
    #   2. a LATER turn does NOT re-inject them — only genuinely new results fold in.
    context 'folding both agents\' results across turns (inject-once)' do
      let(:persona) { instance_double(CubePersona, name: "Jax") }

      # A real record so metadata_json actually persists between PromptBuilder calls.
      let(:conversation) do
        create(:conversation, session_id: "both_lanes_spec").tap do |c|
          c.update!(metadata_json: {
            "pending_ha_results" => [
              { # sound lane → jukebox agent
                "instruction" => "play Otis Redding - Try a Little Tenderness, loud",
                "ha_response" => "Now playing Try a Little Tenderness by Otis Redding, front-and-center.",
                "persona" => "jax", "timestamp" => 20.seconds.ago.iso8601, "processed" => false
              },
              { # action lane → main action agent
                "instruction" => "lights: warm amber over the whole body, slow breathing",
                "ha_response" => "Set the whole cube to a dim warm amber with a slow breathing pulse.",
                "persona" => "jax", "timestamp" => 20.seconds.ago.iso8601, "processed" => false
              }
            ]
          })
        end
      end

      # Fresh prompt_data on EVERY call (own messages array), so injected system
      # notes can't bleed from one turn's result into the next turn's assertions.
      before do
        allow(PromptService).to receive(:build_prompt_for) do
          {
            messages: [
              { role: "system", content: "You are Jax." },
              { role: "user", content: user_message }
            ],
            system_prompt: "You are Jax."
          }
        end
      end

      def injected_results(result)
        result.data[:messages].select { |m| m[:role] == "system" && m[:content].include?("Result:") }
      end

      it 'injects BOTH agents\' results on the next turn, then never again' do
        # --- Turn N+1: both lanes fold in, once each ---
        first = described_class.call(conversation: conversation, persona: persona,
                                     user_message: user_message, context: context)
        first_texts = injected_results(first).map { |m| m[:content] }

        expect(first_texts).to include(
          a_string_including("Otis Redding"),   # sound/jukebox agent
          a_string_including("warm amber")       # main action agent
        )
        expect(first_texts.size).to eq(2)

        # both are now marked processed in the PERSISTED metadata
        expect(conversation.reload.metadata_json["pending_ha_results"].map { |r| r["processed"] })
          .to all(be true)

        # --- Turn N+2: same conversation, nothing new dispatched ---
        second = described_class.call(conversation: conversation, persona: persona,
                                      user_message: "and then what?", context: context)

        expect(injected_results(second)).to be_empty # already-injected results do NOT return
      end

      it 'injects ONLY the newly-added result on a later turn' do
        # Turn N+1 folds in the original two.
        described_class.call(conversation: conversation, persona: persona,
                             user_message: user_message, context: context)

        # A new agent reply lands after that turn.
        md = conversation.reload.metadata_json
        md["pending_ha_results"] << {
          "instruction" => "marquee: THE GRUNT in gold",
          "ha_response" => "Marquee set to THE GRUNT in gold.",
          "persona" => "jax", "timestamp" => Time.current.iso8601, "processed" => false
        }
        conversation.update!(metadata_json: md)

        # Turn N+2 folds in ONLY that new one.
        later = described_class.call(conversation: conversation, persona: persona,
                                     user_message: "keep going", context: context)
        texts = injected_results(later).map { |m| m[:content] }

        expect(texts.size).to eq(1)
        expect(texts.first).to include("THE GRUNT")
      end
    end
  end
end
