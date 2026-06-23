# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Gps', type: :request do
  describe 'GET /api/v1/gps/location' do
    let(:mock_gps_service) { instance_double(Gps::GpsTrackingService) }

    before do
      allow(Gps::GpsTrackingService).to receive(:new).and_return(mock_gps_service)
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

    # NOTE: a "with real data (integration test)" example was removed here. It
    # fought the outer `Gps::GpsTrackingService.new` stub, expected a 'spoofed'
    # source the service never emits, and duplicated coverage already provided by
    # spec/services/gps/gps_tracking_service_spec.rb (real current_location with
    # context merge) and the mocked controller examples above.
  end
end
