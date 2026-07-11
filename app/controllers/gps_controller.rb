# frozen_string_literal: true

# ============================================================
# DORMANT — NOT USED IN THE CURRENT (REGIONAL) ITERATION
# GPS map view for the stationary install; part of the GPS/GIS bundle, none of it wired in. Restore for a future Burn.
# ============================================================

class GpsController < ApplicationController
  def map
    # Serve the GPS map view without layout
    render :map, layout: false
  end
end
