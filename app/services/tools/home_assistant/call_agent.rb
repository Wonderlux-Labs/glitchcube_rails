# app/services/tools/home_assistant/call_agent.rb
class Tools::HomeAssistant::CallAgent < Tools::BaseTool
  def self.description
    "Delegate action requests to Home Assistant's conversation agent for reliable tool execution."
  end

  def self.narrative_desc
    "handle any device control or automation request by passing it to the Home Assistant system"
  end

  def self.prompt_schema
    "call_ha_agent(request: 'turn on the lights and play music') - Pass any device control request to Home Assistant for execution"
  end

  def self.tool_type
    :async  # Execute in background, return personality response immediately
  end

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "call_ha_agent"
      description "Delegate device control and automation requests to Home Assistant's conversation agent"

      parameters do
        string :request, required: true,
               description: "The user's original request for device control, automation, or actions. Pass the full context of what they want done."
      end
    end
  end

  def call(request:)
    Rails.logger.info "🏠 Delegating to HA agent: #{request}"

    begin
      # Call Home Assistant's conversation.process API with tool executor agent
      response = HomeAssistantService.conversation_process(
        text: request,
        agent_id: "tool_executor", # Dedicated HA agent for tool execution
        conversation_id: nil # Don't tie to our conversation - this is a tool call
      )

      Rails.logger.info "✅ HA agent response: #{response.inspect}"

      # Extract execution results
      if response.dig("response", "response_type") == "error"
        error_message = response.dig("response", "speech", "plain", "speech") || "Unknown error"
        return {
          success: false,
          error: error_message,
          message: "Home Assistant couldn't complete that request"
        }
      end

      # Extract successful actions
      success_entities = response.dig("response", "data", "success") || []
      failed_entities = response.dig("response", "data", "failed") || []
      targets = response.dig("response", "data", "targets") || []

      success_count = success_entities.length
      failed_count = failed_entities.length

      if success_count > 0
        success_message = if failed_count > 0
          "Completed #{success_count} actions, but #{failed_count} failed"
        else
          "Successfully completed #{success_count} actions"
        end

        {
          success: true,
          message: success_message,
          actions_taken: success_entities,
          failed_actions: failed_entities,
          targets: targets,
          ha_response: response.dig("response", "speech", "plain", "speech")
        }
      else
        {
          success: false,
          error: "No actions were completed successfully",
          failed_actions: failed_entities,
          message: "Home Assistant couldn't complete any of the requested actions"
        }
      end

    rescue StandardError => e
      Rails.logger.error "❌ HA agent call failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      {
        success: false,
        error: e.message,
        message: "Failed to communicate with Home Assistant"
      }
    end
  end
end
