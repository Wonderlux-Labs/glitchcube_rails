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

  class << self
    # Plays an audio file capped at max_seconds, fading out over the last
    # FADE_SECONDS so a cut-off never sounds like a crash. Shorter files just
    # end naturally (-autoexit; the fade window is past their end).
    def play(path, max_seconds:)
      fade_start = max_seconds - FADE_SECONDS
      run(
        %(ffplay -nodisp -autoexit -loglevel error -t #{max_seconds} ) +
          %(-af "afade=t=out:st=#{fade_start}:d=#{FADE_SECONDS}" #{Shellwords.escape(path.to_s)}),
        timeout: max_seconds + 10
      )
    end

    def say(text, voice: SAY_VOICE)
      run(%(say -v #{voice} #{Shellwords.escape(text)}), timeout: SAY_TIMEOUT)
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
