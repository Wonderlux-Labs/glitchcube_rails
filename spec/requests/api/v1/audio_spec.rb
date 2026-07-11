require 'rails_helper'

RSpec.describe "Audio API", type: :request do
  describe "POST /api/v1/audio/theme_song" do
    it "enqueues a theme song play and returns success" do
      expect {
        post '/api/v1/audio/theme_song', as: :json
      }.to have_enqueued_job(ThemeSongJob).with(nil)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("success" => true)
    end

    it "passes an optional max_seconds cap through to the job" do
      expect {
        post '/api/v1/audio/theme_song', params: { max_seconds: 45 }, as: :json
      }.to have_enqueued_job(ThemeSongJob).with(45)
    end
  end
end
