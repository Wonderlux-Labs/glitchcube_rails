# app/jobs/cube_state_update_job.rb
#
# Pushes a turn's speech + inner_monologue to Home Assistant so a trigger-based
# template sensor (sensor.cube_state, see
# data/homeassistant/packages/glitchcube_cube_state.yaml) can hold them for
# display. Fired as an event rather than a direct state write because
# input_text entities cap out at 255 chars and these can run much longer.
class CubeStateUpdateJob < ApplicationJob
  queue_as :default

  EVENT_TYPE = "glitchcube_cube_state_update"

  def perform(speech:, inner_monologue:)
    return if speech.blank? && inner_monologue.blank?

    HomeAssistantService.instance.fire_event(
      EVENT_TYPE,
      speech: speech.to_s,
      inner_monologue: inner_monologue.to_s
    )
  rescue StandardError => e
    Rails.logger.error "❌ CubeStateUpdateJob failed: #{e.message}"
  end
end
