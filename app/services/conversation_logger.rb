# app/services/conversation_logger.rb
class ConversationLogger
  class << self
    def logger
      @logger ||= begin
        log_file = Rails.root.join("log", "conversation_#{Rails.env}.log")
        logger = Logger.new(log_file, "daily")
        logger.level = Logger::INFO
        logger.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
        end
        logger
      end
    end

    # Conversation lifecycle events
    def conversation_started(session_id, message, persona, context = {})
      logger.info "🎬 CONVERSATION STARTED"
      logger.info "   Session: #{session_id}"
      logger.info "   Persona: #{persona}"
      logger.info "   Message: #{message&.to_s&.length && message.to_s.length > 200 ? message.to_s[0..197] + '...' : message.to_s}"
      logger.info "   Source: #{context[:source] || 'unknown'}"
      logger.info ""
    end

    def llm_request(model, message, response_format = nil)
      logger.info "🤖 LLM REQUEST"
      logger.info "   Model: #{model}"

      # Handle different response_format types
      format_name = case response_format
      when Hash
                     response_format[:name] || "standard"
      when OpenRouter::Schema
                     response_format.name rescue "structured_output"
      else
                     "standard"
      end

      logger.info "   Format: #{format_name}"
      logger.info "   Input: #{message&.to_s&.length && message.to_s.length > 300 ? message.to_s[0..297] + '...' : message.to_s}"
      logger.info ""
    end

    def llm_response(model, response_text, tool_calls = [], metadata = {})
      logger.info "📥 LLM RESPONSE"
      logger.info "   Model: #{model}"
      logger.info "   Content: #{response_text&.truncate(400)}"
      if tool_calls.any?
        logger.info "   Tools Called: #{tool_calls.map { |t| t.is_a?(Hash) ? t[:name] : t.name }.join(', ')}"
      end
      if metadata[:usage]
        logger.info "   Tokens: #{metadata[:usage][:prompt_tokens]}/#{metadata[:usage][:completion_tokens]}"
      end
      logger.info ""
    end

    def tool_execution(tool_name, params, result)
      logger.info "🔧 TOOL EXECUTION"
      logger.info "   Tool: #{tool_name}"
      logger.info "   Params: #{params.inspect}"
      logger.info "   Result: #{result[:success] ? '✅ SUCCESS' : '❌ FAILED'}"
      if result[:message]
        logger.info "   Message: #{result[:message]&.to_s&.length && result[:message].to_s.length > 200 ? result[:message].to_s[0..197] + '...' : result[:message].to_s}"
      end
      if result[:error]
        logger.info "   Error: #{result[:error]}"
      end
      logger.info ""
    end

    def tool_intentions(intentions)
      return if intentions.blank?

      logger.info "🎯 TOOL INTENTIONS (→ HA Agent)"
      intentions.each_with_index do |intent, i|
        # Handle both hash with string keys and symbol keys
        if intent.is_a?(Hash)
          tool_name = intent["tool"] || intent[:tool] || "unknown_tool"
          intent_desc = intent["intent"] || intent[:intent] || intent["description"] || intent[:description] || "no description"
          intent_text = "#{tool_name}: #{intent_desc}"
        else
          intent_text = intent.to_s
        end

        # Safely handle nil intent_text
        intent_text = intent_text&.to_s || "Unknown intention"
        logger.info "   #{i+1}. #{intent_text.length > 150 ? intent_text[0..147] + '...' : intent_text}"
      end
      logger.info ""
    end

    def conversation_ended(session_id, final_response, continue_conversation, _tool_analysis = {}, narrative = {})
      logger.info "🎬 CONVERSATION ENDED"
      logger.info "   Session: #{session_id}"
      # The full structured narrative, surfaced here for manual smoke testing —
      # speech + inner_monologue + actions + continue are the whole response.
      logger.info "   🗣️  Speech: #{final_response}"
      logger.info "   💭 Inner:  #{narrative[:inner_monologue]}" if narrative[:inner_monologue].present?
      log_actions(Array(narrative[:actions]))
      logger.info "   Continue: #{continue_conversation}"
      logger.info "   " + "="*60
      logger.info ""
    end

    # The plain-English actions the brain emitted this turn (before the HA agent
    # translates them). Each is {action_name, description}.
    def log_actions(actions)
      if actions.empty?
        logger.info "   🎛️  Actions: (none)"
        return
      end
      logger.info "   🎛️  Actions:"
      actions.each do |a|
        name = a.is_a?(Hash) ? (a["action_name"] || a[:action_name]) : nil
        desc = a.is_a?(Hash) ? (a["description"] || a[:description]) : a.to_s
        logger.info "      • #{[ name, desc ].compact.join(': ')}"
      end
    end

    # What the HASS conversation agent (the tool caller) reported back after we
    # handed it this turn's actions. Async, so it lands between turns in the log.
    def ha_agent_reply(instruction, reply, error: nil)
      logger.info "🏠 HA AGENT REPLY (tool caller)"
      logger.info "   Sent:  #{instruction}"
      if error
        logger.info "   ⚠️  Error: #{error}"
      else
        logger.info "   Agent: #{reply}"
      end
      logger.info ""
    end

    def error(context, error_message, details = {})
      logger.error "❌ CONVERSATION ERROR"
      logger.error "   Context: #{context}"
      logger.error "   Error: #{error_message}"
      details.each do |key, value|
        logger.error "   #{key.to_s.capitalize}: #{value}"
      end
      logger.error ""
    end

    def persona_switch(from_persona, to_persona, session_id)
      logger.info "🎭 PERSONA SWITCH"
      logger.info "   From: #{from_persona || 'unknown'}"
      logger.info "   To: #{to_persona}"
      logger.info "   Session: #{session_id}"
      logger.info ""
    end

    def debug(message, data = {})
      return unless Rails.env.development?

      logger.debug "🐛 DEBUG: #{message}"
      data.each do |key, value|
        logger.debug "   #{key}: #{value.inspect&.length && value.inspect.length > 300 ? value.inspect[0..297] + '...' : value.inspect}"
      end
      logger.debug ""
    end
  end
end
