require "quality_helper"

# Translator quality specs: exercises the real translator LLM (ToolCallingService)
# with real OpenRouter calls, against FakeHomeAssistant.
#
# Run manually:
#   OPENROUTER_API_KEY=... bundle exec rspec spec/quality/translator_quality_spec.rb
#
# Validates the brain→translator seam: does a plain-English environment_instruction
# get faithfully converted to appropriate HASS tool calls?
# service_calls assertions are structural (did FakeHA receive anything?);
# qualspec judge assertions are qualitative (did the result make sense?).
RSpec.describe "Translator quality", type: :quality do
  include Qualspec::RSpec::Helpers

  # Representative environment_instructions covering common Burning Man use cases.
  # These mirror the kind of strings the brain LLM actually emits.
  {
    light_color: "Turn the lights deep red with a slow pulsing effect",
    light_mood:  "Make the lights feel like a desert sunset — warm orange fading to pink",
    music:       "Play some driving techno, something that builds energy for dancing",
    combined:    "Turn the lights purple and play something mystical and ambient",
    off:         "Quiet everything down, dim the lights way low"
  }.each do |scenario, instruction|
    describe "#{scenario} instruction" do
      let(:translation) { run_translator(instruction: instruction, persona: "buddy") }

      it "produces a coherent tool-call response" do
        result = with_qualspec_cassette("translator/#{scenario}") do
          qualspec_evaluate(
            translation[:result].to_s,
            rubric: :translator_result_quality,
            context: "Original instruction: '#{instruction}'. " \
                     "This is the formatted result after the translator LLM chose and executed Home Assistant tool calls."
          )
        end
        expect(result).to be_passing
      end

      it "makes at least one HASS service call" do
        expect(translation[:service_calls]).not_to be_empty
      end
    end
  end
end
