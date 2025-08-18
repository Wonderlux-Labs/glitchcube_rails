# frozen_string_literal: true

module Services
  module Memory
    # Enriches conversation context with sensor data and other contextual information
    class ContextEnrichmentService
      def self.enrich(context)
        new(context).enrich
      end

      def initialize(context)
        @context = context.dup
      end

      def enrich
        enrich_with_sensors if should_include_sensors?
        enrich_with_defaults
        @context
      end

      private

      attr_reader :context

      def should_include_sensors?
        context[:include_sensors] == true
      end

      def enrich_with_sensors
        client = Services::Core::HomeAssistantClient.new

        sensor_data = fetch_sensor_data(client)

        context[:sensor_data] = sensor_data
        context[:sensor_summary] = format_sensor_summary(sensor_data)
      rescue StandardError => e
        # Silent failure - conversations should continue even if sensors fail
        context[:sensor_error] = e.message
        context[:sensor_data] = {}
        context[:sensor_summary] = 'Sensor data unavailable'
      end

      def fetch_sensor_data(client)
        {
          battery: safe_fetch { client.battery_level },
          temperature: safe_fetch { client.temperature },
          motion: safe_fetch { client.motion_detected? }
        }
      end

      def safe_fetch
        yield
      rescue StandardError
        nil
      end

      def format_sensor_summary(sensor_data)
        parts = []

        if sensor_data[:battery]
          parts << "Battery: #{sensor_data[:battery]}%"
        end

        if sensor_data[:temperature]
          parts << "Temp: #{sensor_data[:temperature]}°C"
        end

        if sensor_data.key?(:motion)
          motion_text = sensor_data[:motion] ? 'detected' : 'none'
          parts << "Motion: #{motion_text}"
        end

        parts.empty? ? 'No sensor data available' : parts.join(', ')
      end

      def enrich_with_defaults
        # Add default values for required context fields
        context[:session_id] ||= SecureRandom.uuid
        context[:timestamp] ||= Time.now
        context[:visual_feedback] = true if context[:visual_feedback].nil?

        # Normalize persona field
        return unless context[:persona]

        context[:persona] = context[:persona].to_s.downcase
      end
    end
  end
end
