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


  config.default_ai_model = ENV["DEFAULT_AI_MODEL"] || "arcee-ai/virtuoso-large"
  config.tool_calling_model = ENV["TOOL_CALLING_MODEL"] || "openai/gpt-5-mini"
  config.two_tier_tools_enabled = ENV["TWO_TIER_TOOLS"] == "true"
end
