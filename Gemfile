source "https://rubygems.org"
ruby "3.3.9"

gem "rails"
gem "propshaft"
gem "pg"
gem "puma"

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "mission_control-jobs"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false


group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "pry-rails"
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "qualspec", github: "estiens/qualspec"
end

group :development do
  gem "web-console"
end

group :test do
  gem "shoulda-matchers"
  gem "vcr"
  gem "webmock"
end

gem "dotenv-rails"
gem "open_router_enhanced", "~> 2.2"
gem "geocoder"

# Vector search / embeddings are not used in this version. Re-enable these
# (plus the enable_extension "vector" migration and the embedding columns)
# if/when memory search comes back.
# gem "langchainrb_rails"
# gem "neighbor"
gem "ruby-openai"

# NOTE: foreman is intentionally NOT bundled. It's a process manager, not an app
# dependency — it's installed directly in this Ruby (rbenv 3.3.9) and invoked as
# bare `foreman` (see bin/dev and bin/glitchcube-boot), never `bundle exec`.
