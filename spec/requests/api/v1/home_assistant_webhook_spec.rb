require 'rails_helper'

RSpec.describe "Home Assistant webhook API", type: :request do
  describe "POST /api/v1/hass/theme_song" do
    it "enqueues a theme song play and returns success" do
      expect {
        post '/api/v1/hass/theme_song', as: :json
      }.to have_enqueued_job(ThemeSongJob).with(nil)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true)
    end

    it "passes an optional max_seconds cap through to the job" do
      expect {
        post '/api/v1/hass/theme_song', params: { max_seconds: 45 }, as: :json
      }.to have_enqueued_job(ThemeSongJob).with(45)
    end
  end

  describe "POST /api/v1/hass/grand_entrance" do
    it "kicks off a random grand-entrance persona switch and returns success" do
      expect(CubePersona).to receive(:set_random).with(entrance: :grand)

      post '/api/v1/hass/grand_entrance', as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true)
    end
  end

  describe "POST /api/v1/hass/glitch_short" do
    it "enqueues the short glitch show and returns success" do
      expect {
        post '/api/v1/hass/glitch_short', as: :json
      }.to have_enqueued_job(ShowJob).with("glitch_short")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true)
    end
  end

  describe "POST /api/v1/hass/glitch_long" do
    it "enqueues the long glitch show and returns success" do
      expect {
        post '/api/v1/hass/glitch_long', as: :json
      }.to have_enqueued_job(ShowJob).with("glitch_long")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true)
    end
  end

  describe "POST /api/v1/hass/restart" do
    before { Rails.cache.delete(Api::V1::HomeAssistantWebhookController::RESTART_CACHE_KEY) }

    it "spawns a detached restart and reports restarted: true" do
      # NEVER actually restart the backend from a test — assert on the spawn instead.
      expect(Process).to receive(:spawn).with(/glitchcube-ctl.* restart/, pgroup: true).and_return(4242)
      expect(Process).to receive(:detach).with(4242)

      post '/api/v1/hass/restart', params: { reason: "test" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("restarted" => true, "reason" => "test")
    end

    it "honors the cooldown and does NOT spawn a second restart" do
      allow(Process).to receive(:spawn).and_return(1)
      allow(Process).to receive(:detach)

      post '/api/v1/hass/restart', as: :json          # first one goes through
      expect(response.parsed_body["data"]).to include("restarted" => true)

      expect(Process).not_to receive(:spawn)          # second is throttled
      post '/api/v1/hass/restart', as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("restarted" => false, "reason" => "cooldown")

  describe "POST /api/v1/hass/idle_announce" do
    it "enqueues the idle musing and returns success" do
      expect {
        post '/api/v1/hass/idle_announce', as: :json
      }.to have_enqueued_job(IdleAnnounceJob)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true)
    end
  end
end
