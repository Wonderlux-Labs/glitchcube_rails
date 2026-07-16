# frozen_string_literal: true

# Recurring heartbeat that keeps Home Assistant's view of the Rails backend LIVE.
#
# Two entities, both ephemeral from HASS's side (a HASS/VM restart wipes them until
# Rails re-pushes), so they must be refreshed on a schedule — not just once at boot:
#
#   * sensor.glitchcube_backend_health  — rich health snapshot (db / HA / llm / uptime)
#   * input_text.backend_health_status  — "online_<ISO8601>" freshness stamp
#
# Before this job existed, the sensor was only ever written by a manual admin click
# and the input_text only by a one-shot boot hook — so after a cold power-cycle (Rails
# boots before the HASS VM is reachable) the push failed and both went stale/"unknown"
# with nothing to recover them. Running every minute makes the state self-heal.
module Recurring
  module System
    class BackendHealthJob < ApplicationJob
      queue_as :default

      def perform
        # Rich sensor. BackendHealthService wraps ALL failures as its own
        # BackendHealthService::Error, so we must rescue broadly below.
        WorldStateUpdaters::BackendHealthService.call

        # Simple freshness stamp the dashboards read.
        HomeAssistantService.call_service(
          "input_text",
          "set_value",
          entity_id: "input_text.backend_health_status",
          value: "online_#{Time.current.iso8601}"
        )
      rescue StandardError => e
        # A heartbeat must NEVER raise: HASS being unreachable (guaranteed for the
        # first minute(s) after a cold boot, since Rails boots before the HASS VM)
        # would otherwise trip SolidQueue's retry backoff and pile up jobs. There is
        # nothing to retry — the next minute's scheduled run self-heals once HASS is up.
        Rails.logger.warn "💓 Backend health heartbeat skipped — #{e.class}: #{e.message}"
      end
    end
  end
end
