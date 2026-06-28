# frozen_string_literal: true

# The cube's curated continuity, injected verbatim into every prompt. A short
# flat file is the single source of truth; every write is mirrored to a Home
# Assistant text sensor so it's visible on a dashboard. The reflection job is
# the only writer in normal operation.
class WorldState
  FILE_PATH = Rails.root.join("storage", "world_state.md")
  SENSOR = "sensor.glitchcube_world_state"

  class << self
    # Current world-state text, or "" if none has been written yet.
    def current
      File.exist?(FILE_PATH) ? File.read(FILE_PATH) : ""
    end

    # Replace the world state, persist to disk, and mirror to Home Assistant.
    def replace(text)
      content = text.to_s.strip
      FileUtils.mkdir_p(FILE_PATH.dirname)
      File.write(FILE_PATH, content)
      mirror_to_home_assistant(content)
      content
    end

    private

    def mirror_to_home_assistant(content)
      HomeAssistantService.instance.set_entity_state(
        SENSOR,
        "updated",
        {
          friendly_name: "GlitchCube World State",
          content: content,
          updated_at: Time.current.iso8601
        }
      )
    rescue StandardError => e
      # The file is the source of truth; a dashboard mirror failure must never
      # break a conversation turn or the reflection job.
      Rails.logger.warn "⚠️ Failed to mirror world state to #{SENSOR}: #{e.message}"
    end
  end
end
