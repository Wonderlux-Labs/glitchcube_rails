# app/services/prompts/persona_loader.rb
module Prompts
  class PersonaLoader
    PERSONA_MAPPING = {
      "buddy" => Personas::BuddyPersona,
      "jax" => Personas::JaxPersona,
      "sparkle" => Personas::SparklePersona,
      "zorp" => Personas::ZorpPersona,
      "lomi" => Personas::LomiPersona,
      "crash" => Personas::CrashPersona,
      "neon" => Personas::NeonPersona,
      "mobius" => Personas::MobiusPersona,
      "thecube" => Personas::ThecubePersona
    }.freeze

    def self.load(persona_name)
      new(persona_name).load
    end

    def initialize(persona_name)
      @persona_name = persona_name&.to_s&.downcase
    end

    def load
      persona_class = PERSONA_MAPPING[@persona_name]

      if persona_class
        persona_class.new
      else
        Rails.logger.warn "⚠️ Unknown persona: #{@persona_name}, defaulting to buddy"
        Personas::BuddyPersona.new
      end
    end
  end
end
