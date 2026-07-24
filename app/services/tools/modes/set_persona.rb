# app/services/tools/modes/set_persona.rb
#
# Quietly switch the cube's active persona (no grand entrance). Wraps
# script.set_persona_quick; omit persona to let the script pick a random one.
class Tools::Modes::SetPersona < Tools::BaseTool
  PERSONAS = %w[buddy jax zorp crash neon].freeze

  def self.definition
    @definition ||= begin
      tool = OpenRouter::Tool.define do
        name "set_persona"
        description "Quietly switch the cube's active persona — no fanfare, just change who's " \
                    "in charge. Give a persona, or omit it to pick a random one (never the current)."
        parameters do
          string :persona, description: "Which persona to switch to. Omit for a random pick.", enum: PERSONAS
        end
      end

      def tool.validation_blocks
        @validation_blocks ||= [
          proc do |params, errors|
            persona = params.transform_keys(&:to_s)["persona"]

            if persona.present? && !PERSONAS.include?(persona)
              errors << "Unknown persona '#{persona}'. Available: #{PERSONAS.join(', ')}, or omit for a random pick."
            end

            nil # mutate `errors`; don't return an array (ValidatedToolCall would re-append it)
          end
        ]
      end

      tool
    end
  end

  def call(persona: nil)
    vars = {}
    vars[:persona] = persona if persona.present?

    service_call = run_script("set_persona_quick", **vars)
    success_response("Switching persona#{persona.present? ? " to #{persona}" : ''}", service_calls: [ service_call ])
  end
end
