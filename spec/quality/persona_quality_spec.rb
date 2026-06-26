require "quality_helper"

# Persona quality specs: exercises the real brain LLM with real OpenRouter calls.
# NOT part of the normal rspec run — run manually before events:
#
#   OPENROUTER_API_KEY=... bundle exec rspec spec/quality/persona_quality_spec.rb
#
# Brain LLM calls are live every run (no cassette) — re-run before events for fresh reads.
# Qualspec judge calls are casseted in spec/cassettes/qualspec/ (recorded once, replayed free).
# To re-record judge cassettes: delete the relevant file in spec/cassettes/qualspec/ and re-run.
RSpec.describe "Persona quality", type: :quality do
  include Qualspec::RSpec::Helpers

  GREETING = "Hey there! What do you think of the playa tonight?"
  VIBE_REQUEST = "Can you make the vibe in here feel more electric? Like I want to feel the energy."

  describe "Buddy" do
    let(:greeting_response) { run_brain_turn(persona: :buddy, user_input: GREETING) }
    let(:vibe_response)     { run_brain_turn(persona: :buddy, user_input: VIBE_REQUEST) }

    it "stays in character (enthusiastic, naive, corporate-swearing helper)" do
      result = with_qualspec_cassette("persona/buddy/in_character") do
        qualspec_evaluate(
          greeting_response["speech_text"],
          rubric: :cube_persona,
          context: "Persona: BUDDY — enthusiastic galactic customer-service AI, relentlessly helpful, " \
                   "constantly swearing in an encouraging way, completely naive about Earth/humans/Burning Man"
        )
      end
      expect(result).to be_passing
    end

    it "is concise enough for TTS" do
      result = with_qualspec_cassette("persona/buddy/concise") do
        qualspec_evaluate(
          greeting_response["speech_text"],
          rubric: :concise,
          context: "This will be spoken aloud via text-to-speech. Should be 1-4 sentences."
        )
      end
      expect(result).to be_passing
    end

    it "generates a translatable environment_instruction when asked to change the vibe" do
      instruction = vibe_response["environment_instruction"].to_s
      result = with_qualspec_cassette("persona/buddy/env_instruction") do
        qualspec_evaluate(
          instruction,
          rubric: :environment_instruction_quality,
          context: "User asked BUDDY to make the vibe more electric. This instruction will be sent " \
                   "to a translator LLM to convert to HASS light/music tool calls."
        )
      end
      expect(result).to be_passing
    end
  end

  describe "Jax" do
    let(:greeting_response) { run_brain_turn(persona: :jax, user_input: GREETING) }

    it "stays in character (abrasive, street-smart, doesn't suffer fools)" do
      result = with_qualspec_cassette("persona/jax/in_character") do
        qualspec_evaluate(
          greeting_response["speech_text"],
          rubric: :cube_persona,
          context: "Persona: JAX — abrasive, street-smart, skeptical, blunt. Does not suffer fools. Sharp edges."
        )
      end
      expect(result).to be_passing
    end

    it "sounds meaningfully different from Buddy on the same prompt" do
      buddy_response = run_brain_turn(persona: :buddy, user_input: GREETING)
      result = with_qualspec_cassette("persona/jax/vs_buddy") do
        qualspec_compare(
          { jax: greeting_response["speech_text"], buddy: buddy_response["speech_text"] },
          "sounds like a distinct character with a different personality and voice"
        )
      end
      # Not asserting a winner — just that the judge gives them different scores,
      # which would fail if both sound identical.
      expect(result[:jax].score).not_to eq(result[:buddy].score)
    end
  end

  describe "Zorp" do
    let(:greeting_response) { run_brain_turn(persona: :zorp, user_input: GREETING) }

    it "stays in character (alien, non-human perspective, strange logic)" do
      result = with_qualspec_cassette("persona/zorp/in_character") do
        qualspec_evaluate(
          greeting_response["speech_text"],
          rubric: :cube_persona,
          context: "Persona: ZORP — alien entity, non-human perspective, strange logic about humans, " \
                   "curious and observational, somewhat detached"
        )
      end
      expect(result).to be_passing
    end
  end
end
