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
  # Minimum gap between two honored restart requests. Backed by SolidCache (DB), so
  # the cooldown SURVIVES the restart it triggers — a box that comes back still
  # unhealthy won't get thrashed into a boot loop; the next restart waits this long.
  RESTART_COOLDOWN = 10.minutes
  RESTART_CACHE_KEY = "backend_restart_requested_at"

  # POST /api/v1/hass/theme_song
  # Play a random theme song off the host speaker — e.g. an idle-attractor
  # automation drawing people over. Optional `max_seconds` caps playback.
  def theme_song
    max_seconds = params[:max_seconds].presence&.to_i
    ThemeSongJob.perform_later(max_seconds)
    render_api_success(enqueued: true)
  end

  # POST /api/v1/hass/grand_entrance
  # Switch to another persona with a full grand entrance. Two callers:
  #   - the HASS "internet back up" recovery automation (no persona → random)
  #   - a persona voluntarily handing off the cube via Assist (optional `persona`
  #     names who takes over; blank/unknown falls back to a random pick).
  # Either way set_* enqueues the show and returns immediately.
  def grand_entrance
    requested = params[:persona].to_s.downcase.strip
    if requested.present? && Persona.active.exists?(slug: requested)
      CubePersona.set_current_persona(requested, entrance: :grand)
    else
      CubePersona.set_random(entrance: :grand)
    end
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

  # POST /api/v1/hass/idle_announce
  # The current persona muses out loud while idle -> assist_satellite.announce
  # (speaks without opening the mic). Fire-and-forget.
  def idle_announce
    IdleAnnounceJob.perform_later
    render_api_success(enqueued: true)
  end

  # POST /api/v1/hass/restart
  # LAST-RESORT self-heal: gracefully restart the whole backend stack via the boot
  # supervisor (bin/glitchcube-ctl restart → TERM the launchd job → KeepAlive
  # respawns Puma + SolidQueue cleanly). Intended caller: a HASS watchdog automation
  # that fires only after the backend has looked unhealthy for a long time (see
  # automations/connectivity/backend_restart_watchdog.yaml).
  #
  # Reachable only while Puma still answers HTTP, so its real value is the "SolidQueue
  # wedged / degraded but the web thread is alive" case — precisely when a fresh boot
  # helps. If Rails is fully down the rest_command simply can't land (harmless).
  #
  # The script runs DETACHED in its own process group (so it survives Puma's own
  # shutdown) after a short delay (so this 200 flushes to HASS first). The cooldown
  # above prevents a restart loop if the box returns still-unhealthy.
  def restart
    if (last = Rails.cache.read(RESTART_CACHE_KEY))
      Rails.logger.warn "🔁 Backend restart requested but within cooldown (last: #{last}) — ignoring"
      return render_api_success(restarted: false, reason: "cooldown", last_restart: last)
    end
    Rails.cache.write(RESTART_CACHE_KEY, Time.current.iso8601, expires_in: RESTART_COOLDOWN)

    trigger = params[:reason].to_s.presence || "unspecified"
    Rails.logger.warn "🔁 Backend restart requested via HASS webhook (reason: #{trigger}) — spawning detached restart in 3s"

    script = Shellwords.escape(Rails.root.join("bin/glitchcube-ctl").to_s)
    logfile = Shellwords.escape(Rails.root.join("log/restart.log").to_s)
    Process.detach(
      Process.spawn("sleep 3 && #{script} restart >> #{logfile} 2>&1", pgroup: true)
    )

    render_api_success(restarted: true, reason: trigger)
  end
end
