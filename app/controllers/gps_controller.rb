# frozen_string_literal: true

class GpsController < ApplicationController
  def map
    # Serve the GPS map view without layout
    render :map, layout: false
  end
end