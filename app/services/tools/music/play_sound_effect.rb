# app/services/tools/music/play_sound_effect.rb
#
# Fire a short stinger SFX through the jukebox speaker. Wraps script.play_sound_effect
# (a fixed enum of effects). Use sparingly — as an accent, not background.
class Tools::Music::PlaySoundEffect < Tools::BaseTool
  EFFECTS = [
    "Applause", "Laugh Track", "Cymbal Crash", "Explosion", "Cha-Ching (Cash Register)",
    "Typewriter Ding", "Bell Ding", "Referee Whistle", "Wind Chime", "Cowbell",
    "Alarm Clock", "Cat Meow", "Dog Bark", "Rooster Crow", "Sheep Bleat"
  ].freeze

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "play_sound_effect"
      description "Fire a short sound-effect stinger through the cube's jukebox speaker for " \
                  "comic or dramatic punctuation. Use sparingly — an accent, not background. " \
                  "Pick one of the available effects."
      parameters do
        string :effect, required: true, description: "Which sound effect to play.", enum: EFFECTS
      end
    end
  end

  def call(effect:)
    return error_response("Unknown sound effect '#{effect}'. Available: #{EFFECTS.join(', ')}.") unless EFFECTS.include?(effect)

    service_call = run_script("play_sound_effect", effect: effect)
    success_response("Playing sound effect: #{effect}", service_calls: [ service_call ])
  end
end
