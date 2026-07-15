# app/controllers/api/v1/home_assistant_webhook_controller.rb
#
# One home for every "HASS pokes Rails to DO something on the host" trigger.
# HASS reaches these via `rest_command` (see
# data/homeassistant/packages/glitchcube_rails_triggers.yaml); HASS is the only
# thing that talks to Rails and they share a box, so this is deliberately plain
# (not RESTful) — just a named action per rest_command. Everything is
# fire-and-forget: enqueue a job or kick off async theater, then return so the
# HTTP call doesn't block HASS.
class Api::V1::HomeAssistantWebhookController < Api::V1::BaseController
  # POST /api/v1/hass/theme_song
  # Play a random theme song off the host speaker — e.g. an idle-attractor
  # automation drawing people over. Optional `max_seconds` caps playback.
  def theme_song
    max_seconds = params[:max_seconds].presence&.to_i
    ThemeSongJob.perform_later(max_seconds)
    render_api_success(enqueued: true)
  end

  # POST /api/v1/hass/grand_entrance
  # Wake the cube: switch to a fresh random persona with a grand entrance. Called
  # by the HASS "internet back up" recovery automation. set_random enqueues the
  # show and returns immediately.
  def grand_entrance
    CubePersona.set_random(entrance: :grand)
    render_api_success(enqueued: true)
  end

  # POST /api/v1/hass/glitch_short
  # A quick glitch fit: one short glitch-radio stab + WLED spasm, lights saved
  # and restored. Fire-and-forget.
  def glitch_short
    ShowJob.perform_later("glitch_short")
    render_api_success(enqueued: true)
  end

  # POST /api/v1/hass/glitch_long
  # The extended glitch-out: long static bed -> short stab -> long bed, WLED
  # glitching throughout, lights saved and restored. Fire-and-forget.
  def glitch_long
    ShowJob.perform_later("glitch_long")
    render_api_success(enqueued: true)
  end
end
