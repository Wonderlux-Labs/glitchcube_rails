# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Gps', type: :request do
  describe 'GET /api/v1/gps/location' do
    let(:mock_gps_service) { instance_double(Services::Gps::GPSTrackingService) }

    before do
      allow(Services::Gps::GPSTrackingService).to receive(:new).and_return(mock_gps_service)
    end

    context 'when GPS data is available' do
      let(:location_data) do
        {
          lat: 40.7864,
          lng: -119.2065,
          timestamp: Time.now,
          source: 'gps',
          accuracy: 3,
          satellites: 8,
          zone: :city,
          address: '6:00 & Esplanade',
          landmarks: [
            { name: 'The Man', type: 'center', distance_meters: 100 }
          ],
          within_fence: true,
          distance_from_man: '328 feet'
        }
      end

      before do
        allow(mock_gps_service).to receive(:current_location).and_return(location_data)
      end

      it 'returns location data successfully' do
        get '/api/v1/gps/location'

        expect(response).to have_http_status(:ok)
        
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:lat]).to eq(40.7864)
        expect(json_response[:lng]).to eq(-119.2065)
        expect(json_response[:source]).to eq('gps')
        expect(json_response[:zone]).to eq('city')
        expect(json_response[:address]).to eq('6:00 & Esplanade')
        expect(json_response[:within_fence]).to be true
      end

      it 'includes GPS metadata' do
        get '/api/v1/gps/location'

        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:accuracy]).to eq(3)
        expect(json_response[:satellites]).to eq(8)
      end

      it 'includes location context' do
        get '/api/v1/gps/location'

        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:landmarks]).to be_present
        expect(json_response[:distance_from_man]).to eq('328 feet')
      end
    end

    context 'when GPS data is not available' do
      before do
        allow(mock_gps_service).to receive(:current_location).and_return(nil)
      end

      it 'returns service unavailable error' do
        get '/api/v1/gps/location'

        expect(response).to have_http_status(:service_unavailable)
        
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:error]).to eq('GPS tracking not available')
        expect(json_response[:message]).to eq('No GPS data - no Home Assistant connection')
        expect(json_response[:timestamp]).to be_present
      end
    end

    context 'when GPS service raises an error' do
      before do
        allow(mock_gps_service).to receive(:current_location).and_raise(StandardError, 'Connection failed')
      end

      it 'returns internal server error' do
        get '/api/v1/gps/location'

        expect(response).to have_http_status(:internal_server_error)
        
        json_response = JSON.parse(response.body, symbolize_names: true)
        expect(json_response[:error]).to eq('GPS service error')
        expect(json_response[:message]).to eq('Connection failed')
        expect(json_response[:timestamp]).to be_present
      end
    end

    context 'with real data (integration test)' do
      before do
        # Load real data if available
        begin
          Rails.application.load_seed if defined?(Rails.application.load_seed)
        rescue StandardError
          # Ignore if seed fails
        end

        # Set spoofed location for testing
        allow(GlitchCube).to receive(:gps_spoofing_allowed?).and_return(true)
        GlitchCube.set_current_location(lat: 40.7864, lng: -119.2065)
      end

      it 'returns location data with real services' do
        # Only run if we have landmark data
        if Landmark.count > 0
          get '/api/v1/gps/location'

          expect(response).to have_http_status(:ok)
          
          json_response = JSON.parse(response.body, symbolize_names: true)
          expect(json_response[:lat]).to eq(40.7864)
          expect(json_response[:lng]).to eq(-119.2065)
          expect(json_response[:source]).to eq('spoofed')
        end
      end
    end
  end
end