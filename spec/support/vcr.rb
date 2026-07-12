require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # STRICT: Block ALL HTTP requests unless explicitly in a VCR cassette
  config.allow_http_connections_when_no_cassette = false

  # Record mode: VCR_RECORD=new_episodes forces re-record of changed interactions
  record_mode = case ENV["VCR_RECORD"]
  when "new_episodes" then :new_episodes
  when "all"          then :all
  when "none"         then :none
  else                     :once
  end

  # Match on method + uri only (not body) — body matching causes permanent drift
  # when model is randomized or gem request format changes between dev/main branches.
  config.default_cassette_options = {
    record: record_mode,
    match_requests_on: [ :method, :uri ]
  }

  # Filter sensitive data
  config.filter_sensitive_data('<OPENROUTER_API_KEY>') { ENV['OPENROUTER_API_KEY'] }
  config.filter_sensitive_data('<HOME_ASSISTANT_TOKEN>') { ENV['HOME_ASSISTANT_TOKEN'] }
  config.filter_sensitive_data('<HOME_ASSISTANT_URL>') { ENV['HOME_ASSISTANT_URL'] }
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }

  # Comprehensive API key pattern filters for common providers
  config.filter_sensitive_data('<OPENAI_API_KEY>') do |interaction|
    interaction.request.headers['Authorization']&.first&.match(/Bearer (sk-proj-[A-Za-z0-9_-]{20,})/)&.[](1)
  end
  config.filter_sensitive_data('<OPENAI_API_KEY>') do |interaction|
    interaction.request.headers['Authorization']&.first&.match(/Bearer (sk-[A-Za-z0-9]{20,})/)&.[](1)
  end
end
