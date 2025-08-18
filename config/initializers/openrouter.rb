# OpenRouter initializer
# Configure your OpenRouter Enhanced gem

require "open_router"

# Configure the gem with our settings
OpenRouter.configure do |config|
  config.access_token = Rails.configuration.openrouter_api_key
  config.site_name = Rails.configuration.openrouter_app_name || "GlitchCube"
  config.site_url = Rails.configuration.openrouter_site_url || "https://glitchcube.dev"

  # Auto-heal structured output responses when models don't support it natively
  config.auto_heal_responses = true
  config.healer_model = "openai/gpt-4o-mini"
  config.max_heal_attempts = 2

  if Rails.configuration.helicone_api_key

              config.uri_base = "https://openrouter.helicone.ai/api"
              config.api_version = "v1"
              config.extra_headers = {
                "Helicone-Auth" => "Bearer #{Rails.configuration.helicone_api_key}"
              }
  end
end
