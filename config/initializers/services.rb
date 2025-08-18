# frozen_string_literal: true

# Ensure Services modules are loaded
Rails.application.config.to_prepare do
  Dir[Rails.root.join("app/services/**/*.rb")].each { |f| require_dependency f }
end
