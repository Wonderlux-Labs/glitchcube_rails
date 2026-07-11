# frozen_string_literal: true

# Generic runner for Shows::* spectacles — enqueue any show by name from
# anywhere (persona switches, automations, the console).
class ShowJob < ApplicationJob
  queue_as :default

  def perform(show_name, **args)
    Rails.logger.info "🎭 Show starting: #{show_name} #{args.inspect}"
    Shows.const_get(show_name.camelize).new(**args).call
    Rails.logger.info "🎭 Show finished: #{show_name}"
  rescue StandardError => e
    Rails.logger.error "🎭 Show #{show_name} crashed: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    raise
  end
end
