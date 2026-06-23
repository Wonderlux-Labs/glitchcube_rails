require "rails_helper"

# Cheapest possible safety net: eager-loads the whole app so any namespace /
# autoloading / syntax regression (the kind `bin/rails zeitwerk:check` catches)
# fails fast here in ~seconds, instead of only blowing up in production boot or
# when a rarely-loaded class is first referenced.
RSpec.describe "Application eager loading" do
  it "eager loads every file without raising" do
    expect { Rails.application.eager_load! }.not_to raise_error
  end
end
