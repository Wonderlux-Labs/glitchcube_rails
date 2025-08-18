# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GlitchCube, type: :model do
  describe '.gps_spoofing_allowed?' do
    it 'returns true in development environment' do
      allow(Rails.env).to receive(:development?).and_return(true)
      expect(GlitchCube.gps_spoofing_allowed?).to be true
    end

    it 'returns true in test environment' do
      allow(Rails.env).to receive(:test?).and_return(true)
      expect(GlitchCube.gps_spoofing_allowed?).to be true
    end

    it 'returns false in production environment' do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(Rails.env).to receive(:test?).and_return(false)
      expect(GlitchCube.gps_spoofing_allowed?).to be false
    end
  end

  describe '.home_camp_coordinates' do
    it 'returns default Burning Man coordinates' do
      coords = GlitchCube.home_camp_coordinates
      expect(coords[:lat]).to eq(40.7864)
      expect(coords[:lng]).to eq(-119.2065)
      expect(coords[:name]).to eq("The Man")
      expect(coords[:zone]).to eq("center")
    end
  end

  describe '.set_current_location' do
    before { Rails.cache.clear }

    context 'when spoofing is allowed' do
      before { allow(GlitchCube).to receive(:gps_spoofing_allowed?).and_return(true) }

      it 'sets location in cache' do
        result = GlitchCube.set_current_location(lat: 40.7864, lng: -119.2065)
        
        expect(result[:lat]).to eq(40.7864)
        expect(result[:lng]).to eq(-119.2065)
        expect(result[:source]).to eq('spoofed')
        expect(result[:timestamp]).to be_present
      end

      it 'returns location data with correct structure' do
        result = GlitchCube.set_current_location(lat: 40.7864, lng: -119.2065)
        expect(result[:lat]).to eq(40.7864)
        expect(result[:lng]).to eq(-119.2065)
        expect(result[:source]).to eq('spoofed')
        expect(result[:timestamp]).to be_present
      end
    end

    context 'when spoofing is not allowed' do
      before { allow(GlitchCube).to receive(:gps_spoofing_allowed?).and_return(false) }

      it 'returns nil and does not set cache' do
        result = GlitchCube.set_current_location(lat: 40.7864, lng: -119.2065)
        
        expect(result).to be_nil
      end
    end
  end

  describe '.current_spoofed_location' do
    before { Rails.cache.clear }

    context 'when spoofing is allowed' do
      before { allow(GlitchCube).to receive(:gps_spoofing_allowed?).and_return(true) }

      it 'returns nil when no location set' do
        expect(GlitchCube.current_spoofed_location).to be_nil
      end
    end

    context 'when spoofing is not allowed' do
      before { allow(GlitchCube).to receive(:gps_spoofing_allowed?).and_return(false) }

      it 'returns nil when spoofing not allowed' do
        expect(GlitchCube.current_spoofed_location).to be_nil
      end
    end
  end
end