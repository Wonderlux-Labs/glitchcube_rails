# frozen_string_literal: true

# Mission Control Jobs configuration - disable HTTP Basic Auth completely
Rails.application.configure do
  config.after_initialize do
    if defined?(MissionControl::Jobs)
      # Completely disable authentication
      MissionControl::Jobs.http_basic_auth_user = nil
      MissionControl::Jobs.http_basic_auth_password = nil

      # Override the authentication method in the base controller
      if defined?(MissionControl::Jobs::ApplicationController)
        MissionControl::Jobs::ApplicationController.class_eval do
          # Override authenticate_by_http_basic to do nothing
          def authenticate_by_http_basic
            # Authentication bypassed for internal access
            true
          end

          # Skip the before_action if it exists
          skip_before_action :authenticate_by_http_basic, raise: false
        end
      end
    end
  end
end
