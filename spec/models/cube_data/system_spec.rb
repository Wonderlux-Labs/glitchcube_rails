# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CubeData::System do
  let(:mock_ha_service) { instance_double(HomeAssistantService) }

  before do
    allow(CubeData).to receive(:ha_service).and_return(mock_ha_service)
    allow(CubeData).to receive(:write_sensor).and_return(true)
    allow(CubeData).to receive(:read_sensor).and_return(nil)
  end

  describe '.update_health' do
    it 'updates backend health sensor' do
      expect(CubeData).to receive(:write_sensor)
        .with(
          "sensor.glitchcube_backend_health",
          "healthy",
          hash_including(
            startup_time: be_a(String),
            last_check: be_a(String)
          )
        )

      expect(CubeData).to receive(:write_sensor)
        .with("input_text.backend_health_status", /healthy at/)

      CubeData::System.update_health("healthy")
    end

    it 'includes additional info in health update' do
      additional_info = { version: "1.0.0", environment: "production" }

      expect(CubeData).to receive(:write_sensor)
        .with(
          "sensor.glitchcube_backend_health",
          "healthy",
          hash_including(additional_info)
        )

      CubeData::System.update_health("healthy", Time.current, additional_info)
    end
  end

  describe '.update_deployment' do
    it 'updates deployment status sensor' do
      expect(CubeData).to receive(:write_sensor)
        .with(
          "sensor.glitchcube_deployment_status",
          "update_available",
          hash_including(
            current_commit: "abc123",
            remote_commit: "def456",
            needs_update: true
          )
        )

      CubeData::System.update_deployment("abc123", "def456", true)
    end
  end

  describe '.update_api_health' do
    it 'updates API health with healthy status' do
      expect(CubeData).to receive(:write_sensor)
        .with(
          "sensor.glitchcube_api_health",
          "healthy",
          hash_including(
            endpoint: "/api/test",
            response_time: 150,
            status_code: 200
          )
        )

      CubeData::System.update_api_health("/api/test", 150, 200)
    end

    it 'updates API health with error status for non-2xx codes' do
      expect(CubeData).to receive(:write_sensor)
        .with(
          "sensor.glitchcube_api_health",
          "error",
          hash_including(status_code: 500)
        )

      CubeData::System.update_api_health("/api/test", 1000, 500)
    end
  end

  describe '.healthy?' do
    it 'returns true when health status is healthy' do
      health_data = { "state" => "healthy" }
      expect(CubeData).to receive(:read_sensor)
        .with("sensor.glitchcube_backend_health")
        .and_return(health_data)

      expect(CubeData::System.healthy?).to be true
    end

    it 'returns false when health status is not healthy' do
      health_data = { "state" => "error" }
      expect(CubeData).to receive(:read_sensor)
        .with("sensor.glitchcube_backend_health")
        .and_return(health_data)

      expect(CubeData::System.healthy?).to be false
    end

    it 'returns false when no health data is available' do
      expect(CubeData).to receive(:read_sensor)
        .with("sensor.glitchcube_backend_health")
        .and_return(nil)

      expect(CubeData::System.healthy?).to be false
    end
  end

  describe '.uptime' do
    it 'calculates uptime from startup time' do
      startup_time = 1.hour.ago
      health_data = {
        "state" => "healthy",
        "attributes" => {
          "startup_time" => startup_time.iso8601
        }
      }

      expect(CubeData).to receive(:read_sensor)
        .with("sensor.glitchcube_backend_health")
        .and_return(health_data)

      uptime = CubeData::System.uptime
      expect(uptime).to be_within(5.seconds).of(1.hour)
    end

    it 'returns 0 when no startup time is available' do
      expect(CubeData).to receive(:read_sensor)
        .with("sensor.glitchcube_backend_health")
        .and_return(nil)

      expect(CubeData::System.uptime).to eq(0)
    end
  end
end
