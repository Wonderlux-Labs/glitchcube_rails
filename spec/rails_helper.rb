# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'

# Load .env for test environment
require 'dotenv'
Dotenv.load('.env')

require_relative '../config/environment'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
# Uncomment the line below in case you have `--require rails_helper` in the `.rspec` file
# that will avoid rails generators crashing because migrations haven't been run yet
# return unless Rails.env.test?
require 'rspec/rails'
require 'shoulda/matchers'
# Add additional requires below this line. Rails is not loaded until this point!

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

# Ensures that the test database schema matches the current schema file.
# If there are pending migrations it will invoke `db:test:prepare` to
# recreate the test database by loading the schema.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [
    Rails.root.join('spec/fixtures')
  ]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # Include FactoryBot methods
  config.include FactoryBot::Syntax::Methods

  # RSpec Rails uses metadata to mix in different behaviours to your tests,
  # for example enabling you to call `get` and `post` in request specs. e.g.:
  #
  #     RSpec.describe UsersController, type: :request do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/8-0/rspec-rails
  #
  # You can also this infer these behaviours automatically by location, e.g.
  # /spec/models would pull in the same behaviour as `type: :model` but this
  # behaviour is considered legacy and will be removed in a future version.
  #
  # To enable this behaviour uncomment the line below.
  # config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  # Disable vectorsearch callbacks in tests to prevent API calls
  config.before(:each) do
    allow_any_instance_of(Event).to receive(:upsert_to_vectorsearch)
    allow_any_instance_of(Summary).to receive(:upsert_to_vectorsearch)

    # Mock Home Assistant API calls to prevent real HTTP requests
    unless described_class == HomeAssistantService || RSpec.current_example.metadata[:allow_ha_calls]
      stub_home_assistant_api_calls
    end
  end
end

# Helper method for stubbing Home Assistant API calls
def stub_home_assistant_api_calls
  # Mock common HomeAssistantService methods (use actual method names)
  allow(HomeAssistantService).to receive(:entity).and_return({ "state" => "unknown", "attributes" => {} })
  allow(HomeAssistantService).to receive(:call_service).and_return(true)
  allow(HomeAssistantService).to receive(:entity_state).and_return("unknown")
  allow(HomeAssistantService).to receive(:history).and_return([])
  allow(HomeAssistantService).to receive(:entities).and_return([])
  allow(HomeAssistantService).to receive(:available?).and_return(true)

  # Mock specific entities that tests commonly check
  allow(HomeAssistantService).to receive(:entity).with("input_select.current_persona")
    .and_return({ "state" => "buddy", "attributes" => { "options" => [ "buddy", "sparkle", "jax" ] } })
  allow(HomeAssistantService).to receive(:entity).with("sensor.boredom_score")
    .and_return({ "state" => "5", "attributes" => {} })
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
