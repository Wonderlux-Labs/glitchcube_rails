# app/services/prompts/persona_loader.rb
module Prompts
  class PersonaLoader
    # Only one persona exists now. The argument is ignored — kept so the many call
    # sites that still pass a persona name don't all need touching.
    def self.load(_persona_name = nil)
      Personas::ArtifactPersona.new
    end

    def self.voice_id_for(_persona_name = nil)
      load.voice_id
    end
  end
end
