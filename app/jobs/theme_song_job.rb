# frozen_string_literal: true

# Fire-and-forget: play a random theme song out the host speaker. Enqueued by
# Api::V1::AudioController#theme_song (HASS hits it via rest_command) so the HTTP
# request returns immediately instead of blocking for the length of the song.
class ThemeSongJob < ApplicationJob
  queue_as :default

  def perform(max_seconds = nil)
    HostAudio.play_random_theme_song(max_seconds: max_seconds)
  end
end
