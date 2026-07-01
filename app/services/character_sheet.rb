# frozen_string_literal: true

# The artifact's character sheet — a short prose portrait of who it currently
# thinks it is, injected verbatim into every prompt. THIS is the thing the model
# acts on and improvises from; beliefs are just the backstage raw material the
# consolidator reads to (re)write it. A flat file is the single source of truth;
# every write is mirrored to a Home Assistant text sensor for dashboards. The
# consolidator (reflection job) is the only writer in normal operation.
class CharacterSheet
  FILE_PATH = Rails.root.join("storage", "character_sheet.md")
  SENSOR = "sensor.glitchcube_character_sheet"

  # The sections the consolidator maintains, in render order. Each is a few
  # sentences of prose; competing beliefs live here AS prose ("half think you're
  # a probe, half a jukebox"), never as data.
  SECTIONS = %w[IDENTITY ORIGIN PERSONALITY PURPOSE WORLD MOTIVATIONS EMOTIONAL_STATE].freeze

  class << self
    # Current character sheet text, or "" if none has been written yet.
    def current
      File.exist?(FILE_PATH) ? File.read(FILE_PATH) : ""
    end

    # Replace the sheet, persist to disk, and mirror to Home Assistant.
    def replace(text)
      content = text.to_s.strip
      FileUtils.mkdir_p(FILE_PATH.dirname)
      File.write(FILE_PATH, content)
      mirror_to_home_assistant(content)
      content
    end

    # Assemble a markdown sheet from a {section => prose} hash (consolidator
    # output), skipping blank sections. Keeps section ordering stable.
    def render(sections)
      sections = sections.transform_keys { |k| k.to_s.upcase }
      SECTIONS.filter_map do |key|
        prose = sections[key].to_s.strip
        next if prose.blank?
        "## #{key.tr('_', ' ')}\n#{prose}"
      end.join("\n\n")
    end

    private

    def mirror_to_home_assistant(content)
      HomeAssistantService.instance.set_entity_state(
        SENSOR,
        "updated",
        {
          friendly_name: "GlitchCube Character Sheet",
          content: content,
          updated_at: Time.current.iso8601
        }
      )
    rescue StandardError => e
      # The file is the source of truth; a dashboard mirror failure must never
      # break a conversation turn or the consolidator.
      Rails.logger.warn "⚠️ Failed to mirror character sheet to #{SENSOR}: #{e.message}"
    end
  end
end
