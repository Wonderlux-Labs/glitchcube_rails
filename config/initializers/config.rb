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
  config.home_assistant_url = ENV["HOME_ASSISTANT_URL"] || (Rails.env.development? || Rails.env.test? ? "http://glitch.local:8123" : nil)
  config.home_assistant_token = ENV["HOME_ASSISTANT_TOKEN"]
  config.home_assistant_timeout = ENV["HOME_ASSISTANT_TIMEOUT"]&.to_i || 30


  # Other integrations can be added here
  # config.service_name_api_key = ENV['SERVICE_NAME_API_KEY']


  # === LLM model roles ===
  # The conversation pipeline uses three distinct LLM roles. Each can be pinned
  # independently via ENV; today they all default to the same fast model, but
  # the split is explicit so roles can be sized separately later.
  #   brain      — the conversation/narrative LLM: decides what to say plus a
  #                single plain-English `environment_instruction`.
  #   translator — turns that one instruction into validated HASS tool calls
  #                (ToolCallingService, run at low temperature).
  #   summarizer — background conversation/daily summarization.
  default_model = ENV["DEFAULT_AI_MODEL"] || "google/gemini-3.1-flash-lite"

  config.brain_model      = ENV["BRAIN_MODEL"]      || default_model
  config.translator_model = ENV["TOOL_CALLING_MODEL"] || default_model
  config.summarizer_model = ENV["SUMMARIZER_MODEL"] || default_model

  # Shared base default for ad-hoc/structured LLM calls that aren't tied to a
  # specific role, plus the timeout/error fallback chain.
  config.default_ai_model = default_model
  config.fallback_models = [ default_model ]
end
