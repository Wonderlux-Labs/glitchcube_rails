require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # STRICT: Block ALL HTTP requests unless explicitly in a VCR cassette
  config.allow_http_connections_when_no_cassette = false

  # Default record mode - will record if cassette doesn't exist
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [ :method, :uri, :body ]
  }

  # Filter sensitive data
  config.filter_sensitive_data('<OPENROUTER_API_KEY>') { ENV['OPENROUTER_API_KEY'] }
  config.filter_sensitive_data('<HOME_ASSISTANT_TOKEN>') { ENV['HOME_ASSISTANT_TOKEN'] }
  config.filter_sensitive_data('<HOME_ASSISTANT_URL>') { ENV['HOME_ASSISTANT_URL'] }
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
end
