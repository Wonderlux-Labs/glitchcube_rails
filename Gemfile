source "https://rubygems.org"
ruby "3.3.9"

gem "rails", "~> 8.0.2", ">= 8.0.2.1"
gem "propshaft"
gem "pg"
gem "puma", ">= 5.0"
gem "jbuilder"

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
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "shoulda-matchers"
end

gem "dotenv-rails", "~> 3.1"
gem "open_router_enhanced", git: "https://www.github.com/estiens/open_router", branch: "dev"
gem "geocoder"
