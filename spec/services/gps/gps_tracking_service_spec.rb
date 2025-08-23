# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Gps::GPSTrackingService, type: :service do
  let(:service) { described_class.new }
  let(:mock_ha_service) { instance_double(HomeAssistantService) }

  before do
    allow(HomeAssistantService).to receive(:new).and_return(mock_ha_service)
    Rails.cache.clear
  end

  describe '#current_location' do
    let(:location_context) do
      {
        zone: :city,
        address: '6:00 & Esplanade',
        landmarks: [],
        within_fence: true
      }
    end

    before do
      allow(Gps::LocationContextService).to receive(:full_context)
        .and_return(location_context)
    end

    context 'when Home Assistant data is available' do
      before do
        allow(mock_ha_service).to receive(:entity).with('sensor.glitchcube_latitude')
          .and_return({ 'state' => '40.7864' })
        allow(mock_ha_service).to receive(:entity).with('sensor.glitchcube_longitude')
          .and_return({ 'state' => '-119.2065' })
        allow(mock_ha_service).to receive(:entity).with('sensor.heltec_htit_tracker_gps_quality')
          .and_return({ 'state' => '3' })
        allow(mock_ha_service).to receive(:entity).with('sensor.heltec_htit_tracker_satellites')
          .and_return({ 'state' => '8' })
        allow(mock_ha_service).to receive(:entity).with('sensor.heltec_htit_tracker_device_uptime')
          .and_return({ 'state' => '3600' })
      end

      it 'returns location with context and GPS metadata' do
        result = service.current_location

        expect(result[:lat]).to eq(40.7864)
        expect(result[:lng]).to eq(-119.2065)
        expect(result[:source]).to eq('gps')
        expect(result[:accuracy]).to eq(3)
        expect(result[:satellites]).to eq(8)
        expect(result[:uptime]).to eq(3600)
        expect(result[:zone]).to eq(:city)
        expect(result[:address]).to eq('6:00 & Esplanade')
      end
    end

    context 'when no GPS data is available' do
      before do
        allow(mock_ha_service).to receive(:entity).and_return(nil)

        # Mock Landmark for fallback
        landmark = instance_double(Landmark, latitude: 40.7864, longitude: -119.2065)
        allow(Landmark).to receive_message_chain(:active, :order).and_return([ landmark ])
      end

      it 'returns fallback location with context' do
        result = service.current_location

        expect(result[:lat]).to eq(40.7864)
        expect(result[:lng]).to eq(-119.2065)
        expect(result[:source]).to eq('random_landmark')
        expect(result[:zone]).to eq(:city)
        expect(result[:address]).to eq('6:00 & Esplanade')
      end
    end

    it 'always returns location data with context merged' do
      allow(mock_ha_service).to receive(:entity).and_return(nil)
      landmark = instance_double(Landmark, latitude: 40.7864, longitude: -119.2065)
      allow(Landmark).to receive_message_chain(:active, :order).and_return([ landmark ])

      result = service.current_location

      expect(result).to include(:lat, :lng, :zone, :address, :landmarks, :within_fence)
    end
  end

  describe '#proximity_data' do
    let(:location_context) do
      {
        landmarks: [
          { name: 'The Man', type: 'center', distance_meters: 100 }
        ],
        nearest_porto: { name: 'Toilet 1', type: 'toilet' }
      }
    end

    before do
      allow(Gps::LocationContextService).to receive(:full_context)
        .and_return(location_context)
    end

    it 'returns proximity data with map mode and effects' do
      result = service.proximity_data(40.7864, -119.2065)

      expect(result[:landmarks]).to eq(location_context[:landmarks])
      expect(result[:portos]).to eq([ location_context[:nearest_porto] ])
      expect(result[:map_mode]).to eq('man')
      expect(result[:visual_effects]).to include(
        { type: 'pulse', color: 'orange', intensity: 'strong' }
      )
    end
  end
end
