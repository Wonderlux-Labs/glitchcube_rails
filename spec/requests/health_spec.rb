require 'rails_helper'

RSpec.describe "Health endpoint", type: :request do
  describe "GET /health" do
    it "returns health status with proper structure" do
      get '/health'
      
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to match(/application\/json/)
      
      json_response = JSON.parse(response.body)
      
      # Check required fields
      expect(json_response).to have_key('status')
      expect(json_response).to have_key('timestamp')
      expect(json_response).to have_key('version')
      expect(json_response).to have_key('uptime')
      expect(json_response).to have_key('services')
      expect(json_response).to have_key('host')
      expect(json_response).to have_key('port')
      
      # Check status values
      expect(['healthy', 'degraded']).to include(json_response['status'])
      
      # Check services structure
      services = json_response['services']
      expect(services).to have_key('database')
      expect(services).to have_key('home_assistant')
      expect(services).to have_key('llm')
      
      # Check service status values
      valid_service_statuses = ['healthy', 'unhealthy', 'not_configured']
      expect(valid_service_statuses).to include(services['database'])
      expect(valid_service_statuses).to include(services['home_assistant'])
      expect(valid_service_statuses).to include(services['llm'])
      
      # Check data types
      expect(json_response['version']).to be_a(String)
      expect(json_response['uptime']).to be_a(Integer)
      expect(json_response['host']).to be_a(String)
      expect(json_response['port']).to be_a(Integer)
      
      # Check timestamp format (ISO8601)
      expect { Time.parse(json_response['timestamp']) }.not_to raise_error
    end
    
    it "returns healthy status when all services are healthy" do
      # Mock all services as healthy
      allow_any_instance_of(HealthController).to receive(:check_database_health).and_return('healthy')
      allow_any_instance_of(HealthController).to receive(:check_home_assistant_health).and_return('healthy')
      allow_any_instance_of(HealthController).to receive(:check_llm_health).and_return('healthy')
      
      get '/health'
      
      json_response = JSON.parse(response.body)
      expect(json_response['status']).to eq('healthy')
    end
    
    it "returns degraded status when any service is unhealthy" do
      # Mock one service as unhealthy
      allow_any_instance_of(HealthController).to receive(:check_database_health).and_return('healthy')
      allow_any_instance_of(HealthController).to receive(:check_home_assistant_health).and_return('unhealthy')
      allow_any_instance_of(HealthController).to receive(:check_llm_health).and_return('healthy')
      
      get '/health'
      
      json_response = JSON.parse(response.body)
      expect(json_response['status']).to eq('degraded')
    end
  end
end