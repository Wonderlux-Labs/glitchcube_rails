# app/services/tools/modes/set_persona.rb
#
# Quietly switch the cube's active persona (no grand entrance). Wraps
# script.set_persona_quick; omit persona to let the script pick a random one.
class Tools::Modes::SetPersona < Tools::BaseTool
  PERSONAS = %w[buddy jax zorp crash neon].freeze

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "set_persona"
      description "Quietly switch the cube's active persona — no fanfare, just change who's " \
                  "in charge. Give a persona, or omit it to pick a random one (never the current)."
      parameters do
        string :persona, description: "Which persona to switch to. Omit for a random pick.", enum: PERSONAS
      end
    end
  end

  def call(persona: nil)
    vars = {}
    vars[:persona] = persona if persona.present?

    service_call = run_script("set_persona_quick", **vars)
    success_response("Switching persona#{persona.present? ? " to #{persona}" : ''}", service_calls: [ service_call ])
  end
end
