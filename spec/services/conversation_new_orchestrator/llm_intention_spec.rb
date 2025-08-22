# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConversationNewOrchestrator::LlmIntention, type: :service do
  let(:prompt_data) do
    {
      system_prompt: "You are a helpful assistant",
      messages: [
        { role: "system", content: "You are a helpful assistant named Buddy" },
        { role: "user", content: "Hello, how are you today?" }
      ],
      context: "Current time: #{Time.current}. User location: Camp Center.",
      tools: []
    }
  end
  let(:user_message) { "Hello, how are you today?" }
  let(:model) { "moonshotai/kimi-k2" }

  let(:service) do
    described_class.new(
      prompt_data: prompt_data,
      user_message: user_message,
      model: model
    )
  end

  describe "#call" do
    subject(:result) { service.call }

    context "with valid parameters", :vcr do
      it "returns success with LLM response data" do
        expect(result).to be_success
        expect(result.data).to be_a(Hash)
        expect(result.data).to have_key(:llm_response)
      end

      it "calls LlmService.call_with_structured_output with correct parameters" do
        expect(LlmService).to receive(:call_with_structured_output).with(
          messages: prompt_data[:messages],
          response_format: Schemas::NarrativeResponseSchema.schema,
          model: model
        ).and_call_original

        result
      end

      it "logs LLM request via ConversationLogger" do
        expect(ConversationLogger).to receive(:llm_request).with(
          model,
          user_message,
          Schemas::NarrativeResponseSchema.schema
        )

        result
      end

      it "logs LLM response via ConversationLogger" do
        expect(ConversationLogger).to receive(:llm_response).with(
          model,
          instance_of(String), # response text
          [], # no tool calls for structured output
          instance_of(Hash) # metadata
        )

        result
      end

      it "uses the correct response schema format" do
        expect(LlmService).to receive(:call_with_structured_output).with(
          hash_including(response_format: Schemas::NarrativeResponseSchema.schema)
        ).and_call_original

        result
      end

      context "with real VCR integration", vcr: { cassette_name: "llm_intention/successful_call" } do
        it "returns structured response matching schema" do
          expect(result).to be_success

          response_data = result.data[:llm_response]

          # Verify required fields from schema
          expect(response_data).to have_key("speech_text")
          expect(response_data).to have_key("continue_conversation")
          expect(response_data).to have_key("inner_thoughts")

          expect(response_data["speech_text"]).to be_a(String)
          expect(response_data["continue_conversation"]).to be_in([ true, false ])
          expect(response_data["inner_thoughts"]).to be_a(String)
        end

        it "handles optional schema fields gracefully" do
          expect(result).to be_success

          response_data = result.data[:llm_response]

          # These fields are optional - should be nil or present
          optional_fields = %w[current_mood pressing_questions goal_progress tool_intents search_memories]
          optional_fields.each do |field|
            if response_data.key?(field)
              expect(response_data[field]).not_to eq("")
            end
          end
        end
      end
    end

    context "error handling" do
      context "when LlmService raises an error" do
        before do
          allow(LlmService).to receive(:call_with_structured_output)
            .and_raise(StandardError.new("OpenRouter API timeout"))
        end

        it "returns failure with error message" do
          expect(result).to be_failure
          expect(result.error).to include("LLM call failed")
          expect(result.error).to include("OpenRouter API timeout")
        end

        it "logs the error via ConversationLogger" do
          expect(ConversationLogger).to receive(:error).with(
            "LlmIntention",
            instance_of(String),
            hash_including(error_class: "StandardError")
          )

          result
        end

        it "does not log successful LLM response" do
          expect(ConversationLogger).not_to receive(:llm_response)
          result
        end
      end

      context "when response format is invalid" do
        before do
          # Mock a response that doesn't match our schema
          allow(LlmService).to receive(:call_with_structured_output)
            .and_return({ invalid: "response" })
        end

        it "returns failure with schema validation error" do
          expect(result).to be_failure
          expect(result.error).to include("Invalid response format")
        end
      end
    end

    context "parameter validation" do
      context "when prompt_data is missing" do
        let(:service) do
          described_class.new(
            prompt_data: nil,
            user_message: user_message,
            model: model
          )
        end

        it "returns failure with validation error" do
          expect(result).to be_failure
          expect(result.error).to include("prompt_data is required")
        end

        it "does not call LlmService" do
          expect(LlmService).not_to receive(:call_with_structured_output)
          result
        end
      end

      context "when prompt_data lacks messages" do
        let(:prompt_data) { { system_prompt: "test", context: "test", tools: [] } }

        it "returns failure with validation error" do
          expect(result).to be_failure
          expect(result.error).to include("prompt_data must contain messages")
        end
      end

      context "when user_message is missing" do
        let(:service) do
          described_class.new(
            prompt_data: prompt_data,
            user_message: nil,
            model: model
          )
        end

        it "returns failure with validation error" do
          expect(result).to be_failure
          expect(result.error).to include("user_message is required")
        end
      end

      context "when user_message is empty string" do
        let(:user_message) { "" }

        it "returns failure with validation error" do
          expect(result).to be_failure
          expect(result.error).to include("user_message cannot be empty")
        end
      end

      context "when model is missing" do
        let(:service) do
          described_class.new(
            prompt_data: prompt_data,
            user_message: user_message,
            model: nil
          )
        end

        it "returns failure with validation error" do
          expect(result).to be_failure
          expect(result.error).to include("model is required")
        end
      end

      context "when model is empty string" do
        let(:model) { "" }

        it "returns failure with validation error" do
          expect(result).to be_failure
          expect(result.error).to include("model cannot be empty")
        end
      end
    end

    context "service initialization" do
      it "can be initialized with all required parameters" do
        expect do
          described_class.new(
            prompt_data: prompt_data,
            user_message: user_message,
            model: model
          )
        end.not_to raise_error
      end

      it "stores parameters as instance variables" do
        service = described_class.new(
          prompt_data: prompt_data,
          user_message: user_message,
          model: model
        )

        expect(service.instance_variable_get(:@prompt_data)).to eq(prompt_data)
        expect(service.instance_variable_get(:@user_message)).to eq(user_message)
        expect(service.instance_variable_get(:@model)).to eq(model)
      end
    end

    context "return data structure" do
      let(:service) do
        described_class.new(
          prompt_data: prompt_data,
          user_message: user_message,
          model: model
        )
      end

      before do
        # Mock successful response
        mock_response = {
          "speech_text" => "Hello! I'm doing great, thank you for asking.",
          "continue_conversation" => true,
          "inner_thoughts" => "The user seems friendly and is greeting me."
        }
        allow(LlmService).to receive(:call_with_structured_output).and_return(mock_response)
      end

      it "returns ServiceResult with expected data structure" do
        expect(result).to be_success
        expect(result).to be_a(ServiceResult)

        data = result.data
        expect(data).to be_a(Hash)
        expect(data).to have_key(:llm_response)
        expect(data[:llm_response]).to be_a(Hash)
      end

      it "preserves all LLM response fields" do
        expect(result).to be_success

        llm_response = result.data[:llm_response]
        expect(llm_response["speech_text"]).to eq("Hello! I'm doing great, thank you for asking.")
        expect(llm_response["continue_conversation"]).to eq(true)
        expect(llm_response["inner_thoughts"]).to eq("The user seems friendly and is greeting me.")
      end
    end

    context "different model types" do
      [ "moonshotai/kimi-k2", "openai/gpt-4o", "anthropic/claude-3.5-sonnet" ].each do |test_model|
        context "with #{test_model} model" do
          let(:model) { test_model }

          it "passes the correct model to LlmService" do
            expect(LlmService).to receive(:call_with_structured_output).with(
              hash_including(model: test_model)
            ).and_return({
              "speech_text" => "Hello!",
              "continue_conversation" => true,
              "inner_thoughts" => "Test response"
            })

            result
          end
        end
      end
    end

    context "logging behavior" do
      let(:mock_response) do
        {
          "speech_text" => "Hello there!",
          "continue_conversation" => true,
          "inner_thoughts" => "User is greeting me",
          "current_mood" => "friendly"
        }
      end

      before do
        allow(LlmService).to receive(:call_with_structured_output).and_return(mock_response)
      end

      it "logs request before LLM call" do
        expect(ConversationLogger).to receive(:llm_request).ordered
        expect(LlmService).to receive(:call_with_structured_output).ordered

        result
      end

      it "logs response after successful LLM call" do
        expect(LlmService).to receive(:call_with_structured_output).ordered
        expect(ConversationLogger).to receive(:llm_response).ordered

        result
      end

      it "logs structured response content correctly" do
        expect(ConversationLogger).to receive(:llm_response).with(
          model,
          "Hello there!", # speech_text becomes the logged content
          [], # no tool calls for structured output
          instance_of(Hash)
        )

        result
      end
    end
  end

  describe "class methods" do
    describe ".call" do
      it "creates instance and calls it" do
        mock_service = double("service", call: ServiceResult.success({}))
        expect(described_class).to receive(:new).with(
          prompt_data: prompt_data,
          user_message: user_message,
          model: model
        ).and_return(mock_service)

        result = described_class.call(
          prompt_data: prompt_data,
          user_message: user_message,
          model: model
        )

        expect(result).to be_success
      end
    end
  end

  describe "integration with conversation flow" do
    context "typical conversation scenario", vcr: { cassette_name: "llm_intention/conversation_flow" } do
      let(:rich_prompt_data) do
        {
          system_prompt: "You are Buddy, a helpful festival guide at Burning Man.",
          messages: [
            { role: "system", content: "You are Buddy, a helpful festival guide." },
            { role: "user", content: "What's the weather like today?" },
            { role: "assistant", content: "Let me check the current conditions for you!" },
            { role: "user", content: "Also, any good events happening tonight?" }
          ],
          context: "Current weather: Sunny, 85°F. Time: 2:30 PM. Location: Center Camp.",
          tools: []
        }
      end
      let(:user_message) { "Also, any good events happening tonight?" }

      it "handles multi-turn conversation context" do
        service = described_class.new(
          prompt_data: rich_prompt_data,
          user_message: user_message,
          model: model
        )

        result = service.call

        expect(result).to be_success
        expect(result.data[:llm_response]).to have_key("speech_text")
        expect(result.data[:llm_response]["speech_text"]).to be_a(String)
        expect(result.data[:llm_response]["speech_text"].length).to be > 10
      end

      it "generates appropriate tool intentions for event queries" do
        service = described_class.new(
          prompt_data: rich_prompt_data,
          user_message: user_message,
          model: model
        )

        result = service.call

        expect(result).to be_success

        # Might generate search intentions for events
        if result.data[:llm_response]["search_memories"]
          expect(result.data[:llm_response]["search_memories"]).to be_an(Array)
        end
      end
    end
  end
end
