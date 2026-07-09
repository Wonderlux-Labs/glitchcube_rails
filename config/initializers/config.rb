# Configuration initializer for loading ENV vars into Rails.configuration
# This is the ONLY place ENV vars should be accessed - use Rails.configuration everywhere else

Rails.application.configure do
  config.mission_control.jobs.http_basic_auth_enabled = false
  # OpenRouter configuration
  config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
  config.openrouter_app_name = ENV["OPENROUTER_APP_NAME"] || "GlitchCube"
  config.openrouter_site_url = ENV["OPENROUTER_SITE_URL"] || "https://glitchcube.com"
  config.helicone_api_key = ENV.fetch("HELICONE_API_KEY", nil)


  # Home Assistant configuration
  config.home_assistant_url = ENV["HOME_ASSISTANT_URL"] ||
    if Rails.env.test?
      "http://glitch.local:8123" # matches recorded VCR cassette hosts — do not change
    elsif Rails.env.development?
      "http://100.79.82.74:8123" # HASS on tailscale (magic name: glitch)
    end
  config.home_assistant_token = ENV["HOME_ASSISTANT_TOKEN"]
  config.home_assistant_timeout = ENV["HOME_ASSISTANT_TIMEOUT"]&.to_i || 30

  # The HASS conversation agent the cube offloads its `actions` to. This agent
  # (an LLM with the Assist API enabled) interprets plain-English requests
  # ("play some jazz", "romantic lights"), controls the exposed devices, and
  # replies in natural language — which we fold back into the next turn's history.
  config.hass_action_agent = ENV["HASS_ACTION_AGENT"] || "conversation.google_gemini_flash_latest"


  # Other integrations can be added here
  # config.service_name_api_key = ENV['SERVICE_NAME_API_KEY']


  # === The one model knob ===
  # We make LLM calls in exactly one place now (the conversation flow), so there
  # is exactly one model, set by one env var (`DEFAULT_AI_MODEL`, always present).
  # Swap it live without a restart: `Rails.configuration.ai_model = "stepfun/step-3.7-flash"`.
  config.ai_model = ENV["DEFAULT_AI_MODEL"]

  # The background summarizer tiers (interaction / persona+handoff / overall) all run on this
  # one model — separate from the conversation brain so we can trade it off independently.
  # Swap live: `Rails.configuration.summarizer_model = "..."`.
  config.summarizer_model = ENV["SUMMARIZER_MODEL"] || "google/gemini-3.5-flash"
end
