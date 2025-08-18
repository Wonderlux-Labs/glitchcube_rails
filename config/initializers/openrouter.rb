# OpenRouter initializer
# Configure your OpenRouter Enhanced gem

require 'open_router'

# Configure the gem with our settings
OpenRouter.configure do |config|
  config.access_token = Rails.configuration.openrouter_api_key
  config.site_name = Rails.configuration.openrouter_app_name || 'GlitchCube'
  config.site_url = Rails.configuration.openrouter_site_url || 'https://glitchcube.dev'
end