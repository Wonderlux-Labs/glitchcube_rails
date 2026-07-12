# Minimal setup for quality specs — separate from rails_helper because quality specs
# make real OpenRouter calls. Do NOT require rails_helper (it configures VCR to block
# all HTTP, which would prevent real LLM calls).
require "dotenv"
Dotenv.load(".env")

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rspec/rails"
require "factory_bot_rails"
require "vcr"
require "webmock"
require "qualspec/rspec"

# VCR config for quality specs: allow real HTTP so brain LLM calls go through.
# with_qualspec_cassette wraps only the judge calls in cassettes.
VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.allow_http_connections_when_no_cassette = true
  config.filter_sensitive_data("<OPENROUTER_API_KEY>") { ENV["OPENROUTER_API_KEY"] }
end

require_relative "support/qualspec_rubrics"
require_relative "support/quality_helpers"

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include QualityHelpers
  config.use_transactional_fixtures = true

  config.before(:each) do
    # Don't execute background jobs during quality turns
    allow(EnvironmentDirectorJob).to receive(:perform_later)
  end

  config.after(:each) do
    HomeAssistantService.reset_instance!
  end
end

Qualspec::RSpec.configure do |config|
  config.default_threshold = 7
  config.vcr_cassette_dir = "spec/cassettes/qualspec"
  config.record_mode = :new_episodes
end
