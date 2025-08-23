# frozen_string_literal: true

# Job to register this server's IP with Home Assistant
# Runs every 5 minutes to ensure registration stays current
module Recurring
  module System
    class HostRegistrationJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "🏠 Running host registration job"

    begin
      # Get the current server's IP and port
      port = ENV.fetch("PORT", 4567)

      # Try to get the external IP (preferably Tailscale IP)
      host_ip = ENV["SERVER_HOST"] || get_external_ip

      if host_ip
        Rails.logger.info "🔄 Updating Home Assistant host registration: #{host_ip}:#{port}"

        # Update the input_text.glitchcube_host entity
        hass_service = HomeAssistantService.new

        result = hass_service.call_service(
          "input_text",
          "set_value",
          entity_id: "input_text.glitchcube_host",
          value: host_ip
        )

        Rails.logger.info "✅ Host registration job completed successfully"
        Rails.logger.debug "📤 Service call result: #{result.inspect}"

      else
        Rails.logger.warn "⚠️ Could not determine host IP for registration"
      end

    rescue HomeAssistantService::ConnectionError => e
      Rails.logger.warn "⚠️ Home Assistant not available for host registration: #{e.message}"
      Rails.logger.warn "💡 This is normal if Home Assistant is not running"
      # Don't re-raise - this is expected when HA is unavailable
    rescue StandardError => e
      Rails.logger.error "❌ Host registration job failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e # Re-raise to trigger SolidQueue retry logic
    end
  end

  private

  def get_external_ip
    # Try multiple methods to get the external IP

    # Method 1: Check for Docker/container environment variables
    return ENV["HOST_IP"] if ENV["HOST_IP"]

    # Method 2: Try to get IP from network interfaces (works in most environments)
    require "socket"
    begin
      # Connect to a remote address to determine which interface to use
      udp_socket = UDPSocket.new
      udp_socket.connect("8.8.8.8", 80)
      ip = udp_socket.addr.last
      udp_socket.close
      return ip if ip && ip != "127.0.0.1"
    rescue StandardError => e
      Rails.logger.debug "Failed to get IP via socket method: #{e.message}"
    end

    # Method 3: Parse network interfaces directly
    begin
      Socket.ip_address_list.each do |addr|
        next unless addr.ipv4?
        next if addr.ipv4_loopback?
        next if addr.ipv4_multicast?
        # Prefer non-private IPs, but accept private ones as fallback
        return addr.ip_address
      end
    rescue StandardError => e
      Rails.logger.debug "Failed to get IP via interface parsing: #{e.message}"
    end

    # Method 4: Fallback to external service (use sparingly)
    begin
      require "net/http"
      response = Net::HTTP.get_response(URI("http://checkip.amazonaws.com/"))
      return response.body.strip if response.code == "200"
    rescue StandardError => e
      Rails.logger.debug "Failed to get IP via external service: #{e.message}"
    end

    nil
  end
    end
  end
end
