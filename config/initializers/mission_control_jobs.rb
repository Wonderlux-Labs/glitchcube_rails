# frozen_string_literal: true

# Mission Control Jobs configuration - no authentication needed
Rails.application.configure do
  config.after_initialize do
    # Disable authentication - private server access only
    MissionControl::Jobs.http_basic_auth_user = nil
    MissionControl::Jobs.http_basic_auth_password = nil
  end
end