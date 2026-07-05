require 'rails_helper'

RSpec.describe "Home Assistant world state trigger", type: :request do
  let(:token) { "test-ha-token" }
  let(:headers) { { "Authorization" => "Bearer #{token}" } }

  before do
    allow(Rails.configuration).to receive(:home_assistant_token).and_return(token)
  end

  # NOTE: the /api/v1/home_assistant/* routes map to a namespaced controller
  # that does not exist (dead routes, return 404). The live endpoint HASS uses
  # is /ha/world_state/trigger, served by the top-level HomeAssistantController.
  def trigger(service_class)
    post "/ha/world_state/trigger",
         params: { service_class: service_class },
         headers: headers
  end

  describe "POST /ha/world_state/trigger" do
    it "executes an allowlisted world state service" do
      expect(WorldStateUpdaters::BackendHealthService).to receive(:call).and_return(true)

      trigger("BackendHealthService")

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("status" => "ok")
    end

    it "rejects a real world state service that is not on the allowlist" do
      # NarrativeConversationSyncService is a real world-state service but is not
      # on the trigger allowlist, so the endpoint must not resolve it by name.
      expect(defined?(WorldStateUpdaters::NarrativeConversationSyncService)).to be_truthy

      trigger("NarrativeConversationSyncService")

      expect(response).to have_http_status(:not_found)
    end

    it "refuses to instantiate or call an arbitrary class (no constantize)" do
      # The historical implementation used constantize, which could resolve any
      # class under the WorldStateUpdaters namespace. Guard against that.
      expect { trigger("Kernel") }.not_to raise_error
      expect(response).to have_http_status(:not_found)

      trigger("ApplicationController")
      expect(response).to have_http_status(:not_found)
    end

    it "returns 400 when service_class is missing" do
      post "/ha/world_state/trigger", params: {}, headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it "requires Home Assistant authentication" do
      post "/ha/world_state/trigger",
           params: { service_class: "BackendHealthService" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
