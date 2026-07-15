# frozen_string_literal: true

require "open3"
require "shellwords"

# The Rails host IS the cube's jukebox: the speaker hangs off this machine, so
# shows play audio by shelling out directly instead of round-tripping through a
# HASS media_player. Stub this module in specs to keep test runs silent.
module HostAudio
  FADE_SECONDS = 5
  SAY_VOICE = "Zarvox" # maximum robot
  SAY_TIMEOUT = 30

  # Fallback cap (percent) when quiet_mode is on but the HASS input_number is
  # missing/blank. Mirrors the input_number's own initial value.
  DEFAULT_QUIET_VOLUME = 50

  # Untracked, gitignored local files (never scped to prod through git). A box
  # without them just no-ops, so a checkout still runs.
  THEME_SONGS_DIR = Rails.root.join("data/rails_media/theme_songs")

  class << self
    # Plays an audio file to its natural end (-autoexit). Pass `max_seconds` to
    # cap it — the last FADE_SECONDS fade out so a cut-off never sounds like a
    # crash — and the run timeout tracks that cap. With no cap the process just
    # runs until the file ends. Pass an explicit `volume` (percent) to set the
    # level; the HASS quiet_mode cap can only ever lower it (see
    # #resolved_volume_percent).
    def play(path, max_seconds: nil, volume: nil)
      vol = resolved_volume_percent(volume)
      parts = [ "ffplay -nodisp -autoexit -loglevel error" ]
      parts << "-t #{max_seconds}" if max_seconds
      parts << "-volume #{vol.round}" if vol
      parts << %(-af "afade=t=out:st=#{max_seconds - FADE_SECONDS}:d=#{FADE_SECONDS}") if max_seconds
      parts << Shellwords.escape(path.to_s)
      run(parts.join(" "), timeout: max_seconds && max_seconds + 10)
    end

    # Picks a random theme song off disk and plays it through the host speaker.
    # Used by the grand-entrance show (capped) and by the /api/v1/hass/theme_song
    # endpoint HASS hits (uncapped, whole song) to draw people over when the cube
    # has been idle. Returns the file played, or nil when the dir is empty.
    def play_random_theme_song(max_seconds: nil, volume: nil)
      song = Dir[THEME_SONGS_DIR.join("*.mp3")].sample
      if song.nil?
        Rails.logger.warn "🎭 No theme songs in #{THEME_SONGS_DIR}; nothing to play"
        return nil
      end

      Rails.logger.info "🎭 Theme song: #{File.basename(song)}"
      play(song, max_seconds: max_seconds, volume: volume)
      song
    end

    def say(text, voice: SAY_VOICE, volume: nil)
      vol = resolved_volume_percent(volume)
      # macOS `say` has no volume flag; the inline [[volm N]] speech command
      # (0.0-1.0) sets it. Only prepended when a volume is in effect.
      spoken = vol ? "[[volm #{(vol / 100.0).round(2)}]]#{text}" : text
      run(%(say -v #{voice} #{Shellwords.escape(spoken)}), timeout: SAY_TIMEOUT)
    end

    # The effective playback volume (percent, 0-100) or nil to leave it
    # untouched. Takes the LOWER of the caller's requested volume and the HASS
    # quiet_mode cap, so quiet mode can only lower a chosen level, never raise
    # it. All four cases collapse to a min over the present values:
    #   neither set → nil (omit volume entirely)   cap only → cap
    #   request only → request                      both → min(request, cap)
    def resolved_volume_percent(requested)
      [ requested, quiet_volume_percent ].compact.min
    end

    # The quiet-hours volume cap (percent) if HASS quiet_mode is on, else nil.
    # Missing entity → state nil → not "on" → nil, so nothing is capped when
    # quiet mode is off. Blank/zero cap falls back to DEFAULT_QUIET_VOLUME.
    def quiet_volume_percent
      return nil unless HomeAssistantService.entity_state("input_boolean.quiet_mode") == "on"

      cap = HomeAssistantService.entity_state("input_number.quiet_mode_max_volume").to_f
      cap.positive? ? cap : DEFAULT_QUIET_VOLUME
    end

    # Not Timeout.timeout: that would orphan a hung player still holding the
    # audio device. Kill it instead (same pattern as CameraDescriptionJob).
    def run(command, timeout:)
      Open3.popen2e(command) do |stdin, stdout, wait_thr|
        stdin.close
        reader = Thread.new { stdout.read } # drain so the child can't block on a full pipe
        unless wait_thr.join(timeout)
          Process.kill("KILL", wait_thr.pid)
          reader.kill # popen2e's ensure closes the pipe; don't leave the drain thread mid-read
          raise "HostAudio command timed out after #{timeout}s: #{command}"
        end
        status = wait_thr.value
        raise "HostAudio command failed (exit #{status.exitstatus}): #{reader.value.to_s.last(500)}" unless status.success?
      end
    end
  end
end
