module WorldStateUpdaters
  # Explicit allowlist of world-state services that may be triggered *by name*
  # from the Home Assistant-facing endpoint and the admin UI.
  #
  # Only no-argument `.call` services belong here. Services that expose a
  # different entry point (e.g. NarrativeConversationSyncService) are
  # intentionally excluded and must be invoked by their own jobs/callers.
  #
  # This replaces the previous `constantize` lookup, which could resolve and
  # invoke arbitrary classes from attacker-controlled input.
  module Registry
    TRIGGERABLE = {
      "BackendHealthService" => BackendHealthService,
      "WeatherForecastSummarizerService" => WeatherForecastSummarizerService
    }.freeze

    # Returns the service class for an allowlisted name, or nil if not allowed.
    def self.fetch(name)
      TRIGGERABLE[name.to_s]
    end

    # Names available for triggering (used by the admin UI).
    def self.names
      TRIGGERABLE.keys
    end
  end
end
