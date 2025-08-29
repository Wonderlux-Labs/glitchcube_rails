# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CubeData do
  let(:mock_ha_service) { instance_double(HomeAssistantService) }

  before do
    allow(CubeData).to receive(:ha_service).and_return(mock_ha_service)
    Rails.cache.clear if CubeData::CACHE_ENABLED
  end

  describe '.sensor_id' do
    it 'returns correct sensor IDs from registry' do
      expect(CubeData.sensor_id(:system, :health)).to eq("sensor.glitchcube_backend_health")
      expect(CubeData.sensor_id(:persona, :current)).to eq("input_select.current_persona")
      expect(CubeData.sensor_id(:lights, :top)).to eq("light.cube_light_top")
    end

    it 'raises error for unknown sensors' do
      expect { CubeData.sensor_id(:unknown, :sensor) }.to raise_error(/Unknown sensor/)
    end
  end

  describe '.read_sensor' do
    let(:sensor_data) { { "state" => "active", "attributes" => { "test" => "value" } } }

    it 'reads sensor data from HomeAssistant' do
      expect(mock_ha_service).to receive(:entity).with("sensor.test").and_return(sensor_data)

      result = CubeData.read_sensor("sensor.test")
      expect(result).to eq(sensor_data)
    end

    it 'handles HomeAssistant errors gracefully' do
      expect(mock_ha_service).to receive(:entity).with("sensor.test").and_raise(StandardError.new("Connection failed"))

      result = CubeData.read_sensor("sensor.test")
      expect(result).to be_nil
    end

    context 'with caching enabled' do
      before { stub_const("CubeData::CACHE_ENABLED", true) }

      it 'caches sensor data' do
        expect(mock_ha_service).to receive(:entity).with("sensor.test").once.and_return(sensor_data)

        # First call should hit HomeAssistant
        result1 = CubeData.read_sensor("sensor.test")
        # Second call should use cache
        result2 = CubeData.read_sensor("sensor.test")

        expect(result1).to eq(sensor_data)
        expect(result2).to eq(sensor_data)
      end
    end
  end

  describe '.write_sensor' do
    context 'for regular sensors' do
      it 'writes sensor state and attributes' do
        expect(mock_ha_service).to receive(:set_entity_state)
          .with("sensor.test", "active", { "test" => "value" })

        result = CubeData.write_sensor("sensor.test", "active", { "test" => "value" })
        expect(result).to be true
      end
    end

    context 'for input entities' do
      it 'handles input_text entities' do
        expect(CubeData).to receive(:call_service)
          .with("input_text", "set_value", { entity_id: "input_text.test", value: "test_value" })

        CubeData.write_sensor("input_text.test", "test_value")
      end

      it 'handles input_select entities' do
        expect(CubeData).to receive(:call_service)
          .with("input_select", "select_option", { entity_id: "input_select.test", option: "option1" })

        CubeData.write_sensor("input_select.test", "option1")
      end
    end

    it 'handles errors gracefully' do
      expect(mock_ha_service).to receive(:set_entity_state).and_raise(StandardError.new("Write failed"))

      result = CubeData.write_sensor("sensor.test", "active")
      expect(result).to be false
    end
  end

  describe '.available?' do
    it 'checks HomeAssistant availability' do
      expect(mock_ha_service).to receive(:available?).and_return(true)

      expect(CubeData.available?).to be true
    end
  end

  describe '.cache_ttl_for_sensor' do
    it 'returns appropriate TTL for system sensors' do
      ttl = CubeData.cache_ttl_for_sensor("sensor.glitchcube_backend_health")
      expect(ttl).to eq(30.seconds)
    end

    it 'returns appropriate TTL for light sensors' do
      ttl = CubeData.cache_ttl_for_sensor("light.cube_light_top")
      expect(ttl).to eq(1.second)
    end

    it 'returns default TTL for unknown sensors' do
      ttl = CubeData.cache_ttl_for_sensor("sensor.unknown")
      expect(ttl).to eq(CubeData::CACHE_TTL)
    end
  end

  describe '.health_check' do
    it 'returns health status' do
      expect(mock_ha_service).to receive(:available?).and_return(true)

      health = CubeData.health_check

      expect(health).to include(
        homeassistant_available: true,
        cached_sensors: be_a(Integer),
        modules_loaded: be_a(Integer),
        total_sensors: be_a(Integer)
      )
    end
  end
end
