# app/controllers/api/v1/audio_controller.rb
#
# Host-speaker audio triggered from outside Rails. The host IS the cube's
# jukebox (see HostAudio), so these endpoints let HASS automations poke it.
# This is the HASS -> Rails direction (the mirror of the custom conversation
# component that calls in): HASS reaches these via `rest_command` (see
# packages/glitchcube_rails_triggers.yaml). Play is fire-and-forget through a
# job so the request returns instead of blocking for the whole clip.
class Api::V1::AudioController < Api::V1::BaseController
  # POST /api/v1/audio/theme_song
  # Play a random theme song off the host speaker — e.g. an idle-attractor
  # automation drawing people over. Optional `max_seconds` caps playback.
  def theme_song
    max_seconds = params[:max_seconds].presence&.to_i
    ThemeSongJob.perform_later(max_seconds)
    render_api_success(enqueued: true)
  end
end
