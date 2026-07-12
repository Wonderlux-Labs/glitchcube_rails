# app/jobs/camera_description_job.rb
require "open3"

#
# The cube's "look": grab one frame from the webcam (plugged into this machine —
# no RTSP/streaming; the camera is off between captures), ask a vision model what
# it sees, and stash the short description in input_text.current_camera_state —
# the same entity ContextBuilder injects into the brain's prompt and the HASS
# "Camera: clear stale description" automation blanks after 3 min. Enqueued
# fire-and-forget at the start of every conversation turn; the throttle below
# makes that a cheap no-op most of the time.
#
# Fails loudly on purpose (no rescues beyond the vision fallback inside
# LlmService.call_with_vision): a broken capture shows up as a failed job, and
# the old description simply ages out via the HASS clear automation.
class CameraDescriptionJob < ApplicationJob
  queue_as :default

  SNAPSHOT_DIR = Rails.root.join("tmp/camera")
  # The full capture command, deliberately visible in one place — no knobs. One
  # frame, then the camera turns back off. %{path} is the timestamped output file.
  # -framerate 30: the prod webcam only offers exactly 30fps at 1280x720; without
  # this ffmpeg picks its 29.97 default, which the device rejects with an I/O error
  # before it ever opens. -update 1: ffmpeg 8's image2 muxer refuses a single fixed
  # filename (no %03d sequence pattern) unless told it's a single-image overwrite.
  SNAPSHOT_COMMAND = %(ffmpeg -f avfoundation -framerate 30 -video_size 1280x720 -pixel_format uyvy422 -i "0" -update 1 -frames:v 1 -y %{path})
  THROTTLE_SECONDS = 120
  CAPTURE_TIMEOUT = 10 # seconds; a hung ffmpeg is killed and fails the job
  CAMERA_STATE_ENTITY = "input_text.current_camera_state" # same entity ContextBuilder reads
  DISABLE_ENTITY = "input_boolean.disable_camera" # HASS-side kill switch (timer/automation-friendly)
  DESCRIPTION_MAX = 255 # the input_text's max length

  # People-focused, present-tense. Deliberately states NO character count: qwen3-vl
  # takes a "max 255 characters" instruction literally and appends a "(193 chars)"
  # tally to its answer. write_description truncates to DESCRIPTION_MAX anyway, so we
  # ask for brevity in words, not numbers. "Only what you can actually see" trims the
  # model's tendency to narrate a backstory for the scene.
  VISION_PROMPT = <<~PROMPT.squish
    You are the eyes of an interactive art cube; this is the snapshot it just took of
    whoever is in front of it. In two to three short sentences, describe only what you can
    actually see: how many people, their fashion / vibe, and anything notable. Be brief
    and concrete — no guessing or backstory. If it's too dark to see or no on is there, just say that.
    This provides context for in-character interactions with whomever the cube is interacting with
    so details are important. Do not include any commentary.
  PROMPT

  def perform(throttle_seconds: nil)
    return if camera_disabled?
    return if throttled?(throttle_seconds || THROTTLE_SECONDS)

    snapshot_path = capture_snapshot!
    description = if Rails.configuration.use_local_vision
      LlmService.call_with_local_vision(prompt: VISION_PROMPT, image_path: snapshot_path)
    else
      LlmService.call_with_vision(prompt: VISION_PROMPT, image_path: snapshot_path)
    end
    write_description(description)
  end

  private

  # Two kill switches: Rails config (DISABLE_CAMERA env / live config toggle, also
  # checked at enqueue time) and the HASS input_boolean, so HASS automations — a
  # nighttime timer, say — can turn the look off without touching Rails.
  def camera_disabled?
    if Rails.configuration.disable_camera
      Rails.logger.info "📷 Camera disabled via Rails config; skipping"
      return true
    end
    if HomeAssistantService.instance.entity(DISABLE_ENTITY)&.dig("state") == "on"
      Rails.logger.info "📷 Camera disabled via #{DISABLE_ENTITY}; skipping"
      return true
    end
    false
  end

  # Mirrors the old HASS automation's debounce: an empty description always
  # refreshes (a new conversation right after a clear gets a look immediately),
  # otherwise at most one look per throttle window. Keyed on last_updated so an
  # identical back-to-back description still counts as a refresh.
  def throttled?(throttle_seconds)
    entity = HomeAssistantService.instance.entity(CAMERA_STATE_ENTITY)
    return false if entity.nil? || entity["state"].to_s.strip.empty?

    last_updated = entity["last_updated"]
    return false if last_updated.blank?

    fresh = Time.zone.parse(last_updated.to_s) > throttle_seconds.seconds.ago
    Rails.logger.info "📷 Camera description still fresh (< #{throttle_seconds}s); skipping" if fresh
    fresh
  end

  # Snapshots are kept (timestamped, never overwritten) so consecutive frames stay
  # available for future image diffing. No cleanup yet — truncate to the last ~10
  # when disk bloat starts to matter.
  def capture_snapshot!
    FileUtils.mkdir_p(SNAPSHOT_DIR)
    path = SNAPSHOT_DIR.join("snapshot_#{Time.current.utc.strftime('%Y%m%d_%H%M%S')}.jpg")
    command = format(SNAPSHOT_COMMAND, path: path)

    Rails.logger.info "📷 Capturing snapshot → #{path.basename}"
    output, status = run_capture(command)
    raise "Snapshot capture failed (exit #{status.exitstatus}): #{output.to_s.last(500)}" unless status.success?
    raise "Snapshot capture produced no file at #{path}" unless File.size?(path)

    path.to_s
  end

  # Not Timeout.timeout: that would fail the job but orphan a hung ffmpeg still
  # holding the camera device open, wedging every later capture. Kill it instead.
  def run_capture(command)
    Open3.popen2e(command) do |stdin, stdout, wait_thr|
      stdin.close
      reader = Thread.new { stdout.read } # drain the pipe so ffmpeg can't block on a full buffer
      unless wait_thr.join(CAPTURE_TIMEOUT)
        Process.kill("KILL", wait_thr.pid)
        raise "Snapshot capture timed out after #{CAPTURE_TIMEOUT}s; killed ffmpeg"
      end
      [ reader.value, wait_thr.value ]
    end
  end

  def write_description(description)
    value = description.to_s.squish.truncate(DESCRIPTION_MAX)
    HomeAssistantService.instance.call_service(
      "input_text", "set_value",
      entity_id: CAMERA_STATE_ENTITY, value: value
    )
    Rails.logger.info "📷 Camera description updated: #{value}"
  end
end
