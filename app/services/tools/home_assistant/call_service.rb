# app/services/tools/home_assistant/call_service.rb
class Tools::HomeAssistant::CallService < Tools::BaseTool
  def self.description
    "Call any Home Assistant service with custom parameters - fallback for advanced operations"
  end
  
  def self.prompt_schema
    "call_hass_service(domain: 'climate', service: 'set_temperature', service_data: {entity_id: 'climate.thermostat', temperature: 72}) - Call any Home Assistant service"
  end
  
  def self.tool_type
    :async # Service calls happen after response (most are control actions)
  end
  
  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "call_hass_service"
      description "Call any Home Assistant service with custom parameters. Use this for operations not covered by specific light tools."
      
      parameters do
        string :domain, required: true,
               description: "Service domain (e.g., 'light', 'switch', 'climate', 'automation')",
               enum: -> { Tools::HomeAssistant::CallService.available_domains }
        
        string :service, required: true,
               description: "Service name within the domain (e.g., 'turn_on', 'set_temperature')"
        
        object :service_data,
               description: "Service-specific data (e.g., entity_id, brightness, temperature)",
               properties: {
                 entity_id: {
                   type: "string",
                   description: "Target entity ID (most services require this)"
                 }
               }
      end
    end
  end
  
  def self.available_domains
    # Cache available domains from Home Assistant
    @available_domains ||= begin
      service = HomeAssistantService.instance
      services = service.services rescue []
      
      if services.is_a?(Array)
        services.map { |s| s['domain'] }.compact.sort.uniq
      else
        # Fallback common domains
        %w[
          automation climate cover fan input_boolean input_number input_select
          light media_player scene script switch vacuum
        ]
      end
    end
  end
  
  def call(domain:, service:, service_data: {})
    # Validate service exists
    begin
      available_services = HomeAssistantService.services
      
      unless available_services.is_a?(Array)
        return error_response("Could not retrieve available services from Home Assistant")
      end
      
      domain_service = available_services.find { |s| s['domain'] == domain }
      
      unless domain_service
        available_domains = available_services.map { |s| s['domain'] }.sort
        return error_response(
          "Domain '#{domain}' not found",
          domain: domain,
          available_domains: available_domains
        )
      end
      
      domain_services = domain_service['services'] || {}
      
      unless domain_services.key?(service)
        available_service_names = domain_services.keys.sort
        return error_response(
          "Service '#{service}' not found in domain '#{domain}'",
          domain: domain,
          service: service,
          available_services: available_service_names
        )
      end
      
      # Validate entity_id if provided
      if service_data[:entity_id] || service_data['entity_id']
        entity_id = service_data[:entity_id] || service_data['entity_id']
        entity = validate_entity(entity_id)
        
        if entity.is_a?(Hash) && entity[:error]
          return entity # Return validation error
        end
      end
      
      # Call the service
      result = HomeAssistantService.call_service(domain, service, service_data)
      
      success_response(
        "Called #{domain}.#{service}" +
        (service_data[:entity_id] ? " on #{service_data[:entity_id]}" : ""),
        {
          domain: domain,
          service: service,
          service_data: service_data,
          service_result: result
        }
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to call service: #{e.message}")
    end
  end
end