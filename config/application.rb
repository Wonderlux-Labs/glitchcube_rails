require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module GlitchcubeRails
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Use SQL structure format instead of schema.rb for PostGIS compatibility
    config.active_record.schema_format = :sql

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Add services directory to autoload paths for development reloading
    config.autoload_paths += %W[#{config.root}/app/services]

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Pacific Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Clear all SolidQueue jobs on Rails start (persistence not important)
    config.after_initialize do
      if defined?(SolidQueue::Job)
        begin
          jobs_cleared = SolidQueue::Job.count
          if jobs_cleared > 0
            Rails.logger.info "🧹 Clearing #{jobs_cleared} SolidQueue jobs on startup"
            SolidQueue::Job.delete_all
            Rails.logger.info "🧹 Successfully cleared all SolidQueue jobs"
          else
            Rails.logger.info "🧹 No SolidQueue jobs to clear on startup"
          end
        rescue => e
          Rails.logger.warn "🧹 Failed to clear SolidQueue jobs: #{e.message}"
        end
      end

      # Update backend health sensor on startup
      begin
        Rails.logger.info "💓 Updating backend health sensor on startup"
        startup_time = Time.current.iso8601

        HomeAssistantService.call_service(
          "input_text",
          "set_value",
          entity_id: "input_text.backend_health_status",
          value: "online_#{startup_time}"
        )

        Rails.logger.info "💓 Backend health sensor updated successfully"
      rescue => e
        Rails.logger.warn "💓 Failed to update backend health sensor: #{e.message}"
      end
    end
  end
end
