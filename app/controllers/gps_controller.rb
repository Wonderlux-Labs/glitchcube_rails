# frozen_string_literal: true

class GpsController < ApplicationController
  def map
    # Serve the GPS map view
    render :map
  end
end