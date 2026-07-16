# Configuration initializer for loading ENV vars into Rails.configuration.
# This is the ONLY place ENV vars should be accessed — use Rails.configuration everywhere else.
#
# This file is the source of truth for every knob and its default. `.env` (gitignored)
# should hold only two kinds of thing:
#   1. REQUIRED SECRETS — API keys / tokens with no default. Missing ones fail loudly at
#      boot (see require_secret below); dev + prod .env must set them. Test uses a dummy.
#   2. GENUINE PER-HOST OVERRIDES — values that legitimately differ by machine (e.g.
#      USE_LOCAL_VISION on the dev box, PGGSSENCMODE for local libpq).
# Everything else defaults sensibly and needs NO env var on any host; set the matching
# ENV only to override. Optional vars are read with ENV.fetch(key, default). Don't
# reintroduce env vars for things that just want a per-environment default — put the
# default here instead.

Rails.application.configure do
  # Required secrets: fail loudly at boot if unset. Tests use VCR/fakes and need no real
  # credentials, so they fall back to a dummy rather than raising.
  require_secret = lambda do |key|
    ENV.fetch(key) do
      raise "Missing required env var #{key} — set it in .env (see config/initializers/config.rb)" unless Rails.env.test?

      "test-dummy-#{key.downcase}"
    end
  end

  config.mission_control.jobs.http_basic_auth_enabled = false

  # OpenRouter configuration
  config.openrouter_api_key = require_secret.call("OPENROUTER_API_KEY")
  config.openrouter_app_name = ENV.fetch("OPENROUTER_APP_NAME", "GlitchCube")
  config.openrouter_site_url = ENV.fetch("OPENROUTER_SITE_URL", "https://glitchcube.com")
  config.helicone_api_key = ENV.fetch("HELICONE_API_KEY", nil)

  # Home Assistant configuration
  config.home_assistant_token = require_secret.call("HOME_ASSISTANT_TOKEN")
  # Dev and prod hit the SAME HASS instance, reachable at glitch.local. Overridable
  # per host via HOME_ASSISTANT_URL, but nothing sets it now. Test also relies on this
  # exact host to match recorded VCR cassettes — do not change it.
  config.home_assistant_url = ENV.fetch("HOME_ASSISTANT_URL", "http://glitch.local:8123")
  config.home_assistant_timeout = ENV.fetch("HOME_ASSISTANT_TIMEOUT", "30").to_i

  # The cube offloads its plain-English action channels to HASS conversation agents
  # (LLMs with the Assist API enabled) that own ALL the tool-calling — picking devices,
  # resolving "romantic lights" to RGB, retrying — and reply in natural language, which
  # we fold back into the next turn's history. There are two lanes, dispatched in
  # parallel (see ConversationOrchestrator::ActionExecutor):
  #   - hass_action_agent — lights, marquee, other_actions, and anything else.
  #   - hass_sound_agent  — the `sound` channel only (the jukebox: searching the
  #     library, deciding what to play), which is slower and more iterative.
  # These are straight config, not env-overridden: each points at a dedicated HASS
  # conversation agent. To change behavior, switch the MODEL on that agent in Home
  # Assistant (config_entries subentry) — no Rails change needed.
  config.hass_action_agent = "conversation.default_hass_tools_agent"
  config.hass_sound_agent  = "conversation.glitchcube_jukebox_agent"

  # === The one model knob ===
  # We make LLM calls in exactly one place now (the conversation flow), so there
  # is exactly one brain model. It has a sane default here, so no env var is
  # required on any host; set `DEFAULT_AI_MODEL` only to override for a run.
  # Swap it live without a restart: `Rails.configuration.ai_model = "stepfun/step-3.7-flash"`.
  config.ai_model = ENV.fetch("DEFAULT_AI_MODEL", "deepseek/deepseek-v4-flash:nitro")

  # The background summarizer tiers (interaction / persona+handoff / overall) all run on this
  # one model — separate from the conversation brain so we can trade it off independently.
  # Swap live: `Rails.configuration.summarizer_model = "..."`.
  config.summarizer_model = ENV.fetch("SUMMARIZER_MODEL", "google/gemini-3.5-flash")

  # Camera snapshot description (CameraDescriptionJob → LlmService.call_with_vision).
  # Vision-capable models only. If the primary raises or comes back empty we retry once
  # on the fallback, then fail loudly. Swap live like the other model knobs.
  config.camera_vision_model = ENV.fetch("CAMERA_VISION_MODEL", "google/gemini-3.5-flash")
  config.vision_fallback_model = ENV.fetch("VISION_FALLBACK_MODEL", "qwen/qwen3.7-max")

  # Local vision: describe the camera snapshot with an ollama vision model running on
  # the same host (no image ever leaves the box — the privacy win for the Burn). When
  # true, CameraDescriptionJob calls LlmService.call_with_local_vision, which POSTs to
  # ollama and, if that fails (ollama down, timeout), falls back to the OpenRouter
  # call_with_vision path above. Set false to skip ollama entirely and go straight to
  # OpenRouter. Warm latency ~2.5s on prod; ~7s cold (model load).
  # On by default: only an explicit USE_LOCAL_VISION="false" disables it (a missing
  # var, or any other value like "1", stays true).
  config.use_local_vision = ENV.fetch("USE_LOCAL_VISION", "true") != "false"
  config.local_vision_url = ENV.fetch("LOCAL_VISION_URL", "http://localhost:11434")
  config.local_vision_model = ENV.fetch("LOCAL_VISION_MODEL", "qwen3-vl:4b")

  # Odds (percent) that a turn "glitches" and leaks the inner monologue out loud
  # instead of the intended speech (ResponseSynthesizer). Forced to 0 in test so
  # it never fires unless a spec exercises it deliberately. Swap live like the
  # other knobs: `Rails.configuration.glitch_percent = 10`.
  config.glitch_percent = Rails.env.test? ? 0 : ENV.fetch("GLITCH_PERCENT", "3").to_i

  # Kill switch for the camera pipeline. When true, no CameraDescriptionJob is ever
  # enqueued and ContextBuilder omits the camera block. Toggle live like the model
  # knobs, or flip input_boolean.disable_camera on the HASS side (checked in the job —
  # automation/timer-friendly, e.g. "camera off at night").
  config.disable_camera = ENV.fetch("DISABLE_CAMERA", nil) == "true"
end
