# frozen_string_literal: true

# CubeData Initializer
# This initializes the CubeData system on Rails startup

Rails.application.configure do
  # Initialize CubeData after the application is booted
  config.after_initialize do
    begin
      # Only initialize if HomeAssistant is configured
      if Rails.configuration.respond_to?(:home_assistant_url) &&
         Rails.configuration.home_assistant_url.present?

        CubeData.initialize!

        Rails.logger.info "✅ CubeData initialized successfully"
      else
        Rails.logger.warn "⚠️  CubeData not initialized - HomeAssistant not configured"
      end
    rescue => e
      Rails.logger.error "❌ CubeData initialization failed: #{e.message}"
      # Don't fail the app if CubeData fails to initialize
    end
  end
end
