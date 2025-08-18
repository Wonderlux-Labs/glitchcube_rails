# Register this server's IP and port with Home Assistant on startup
Rails.application.config.after_initialize do
  # Run in development and production for automatic dev rerouting
  if Rails.env.development? || Rails.env.production? || ENV['REGISTER_HOST_ON_STARTUP'] == 'true'
    begin
      # Get the current server's IP and port
      port = ENV.fetch("PORT", 4567)
      
      # Try to get the external IP
      # In production, this might be set via environment variable
      host_ip = ENV['SERVER_HOST'] || get_external_ip
      
      if host_ip
        Rails.logger.info "🏠 Registering host with Home Assistant: #{host_ip}:#{port}"
        
        # Update the input_text.glitchcube_host entity (just IP, not port)
        hass_service = HomeAssistantService.new
        
        Rails.logger.info "🔍 Current input_text.glitchcube_host value before update: #{hass_service.entity_state('input_text.glitchcube_host')}"
        
        # Use the correct input_text service call format (matching our existing pattern)
        result = hass_service.call_service(
          'input_text',
          'set_value',
          entity_id: 'input_text.glitchcube_host',
          value: host_ip
        )
        
        Rails.logger.info "📤 Service call result: #{result.inspect}"
        
        # Wait a moment for the update to propagate
        sleep(1)
        
        # Verify the update worked
        current_value = hass_service.entity_state('input_text.glitchcube_host')
        Rails.logger.info "📋 Current input_text.glitchcube_host value after update: #{current_value}"
        
        if current_value == host_ip
          Rails.logger.info "✅ Host registration verified successful"
        else
          Rails.logger.warn "⚠️ Host registration may have failed - expected #{host_ip}, got #{current_value}"
        end
        
        Rails.logger.info "✅ Successfully registered host: #{host_ip}:#{port}"
        
        # Set a rails config for the registered URL for reference
        Rails.application.config.registered_host = "#{host_ip}:#{port}"
        
      else
        Rails.logger.warn "⚠️ Could not determine host IP for registration"
      end
      
    rescue StandardError => e
      Rails.logger.error "❌ Failed to register host with Home Assistant: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  else
    Rails.logger.info "🏠 Host registration skipped (test environment)"
  end
end

private

def get_external_ip
  # Try multiple methods to get the external IP
  
  # Method 1: Check for Docker/container environment variables
  return ENV['HOST_IP'] if ENV['HOST_IP']
  
  # Method 2: Try to get IP from network interfaces (works in most environments)
  require 'socket'
  begin
    # Connect to a remote address to determine which interface to use
    udp_socket = UDPSocket.new
    udp_socket.connect('8.8.8.8', 80)
    ip = udp_socket.addr.last
    udp_socket.close
    return ip if ip && ip != '127.0.0.1'
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
    require 'net/http'
    response = Net::HTTP.get_response(URI('http://checkip.amazonaws.com/'))
    return response.body.strip if response.code == '200'
  rescue StandardError => e
    Rails.logger.debug "Failed to get IP via external service: #{e.message}"
  end
  
  nil
end