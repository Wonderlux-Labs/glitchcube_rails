# app/controllers/admin/conversations_controller.rb

class Admin::ConversationsController < Admin::BaseController
  def index
    @conversations = Conversation.includes(:conversation_logs, :conversation_memories)
                                .order(created_at: :desc)
                                .limit(50)

    # Simple filters
    if params[:status] == "active"
      @conversations = @conversations.active
    elsif params[:status] == "finished"
      @conversations = @conversations.finished
    end

    if params[:persona].present?
      @conversations = @conversations.by_persona(params[:persona])
    end
  end

  def show
    @conversation = Conversation.find(params[:id])
    @logs = @conversation.conversation_logs.chronological
    @memories = @conversation.conversation_memories.recent
    @tools_used = extract_tools_from_logs(@logs)
  end

  def timeline
    @conversation = Conversation.find(params[:id])
    @timeline_events = build_timeline(@conversation)
    render json: @timeline_events
  end

  def tools
    @conversation = Conversation.find(params[:id])
    @tools = extract_detailed_tools(@conversation)
    render json: @tools
  end

  private

  def extract_tools_from_logs(logs)
    tools = []
    logs.each do |log|
      tool_results = log.tool_results_json
      if tool_results.present?
        tools << {
          log_id: log.id,
          timestamp: log.created_at,
          tools: tool_results
        }
      end
    end
    tools
  end

  def build_timeline(conversation)
    events = []

    # Conversation start
    events << {
      type: "conversation_start",
      timestamp: conversation.started_at,
      title: "Conversation Started",
      details: "Persona: #{conversation.persona}"
    }

    # Each log entry
    conversation.conversation_logs.chronological.each do |log|
      events << {
        type: "message_exchange",
        timestamp: log.created_at,
        title: "Message Exchange",
        user_message: log.user_message.truncate(100),
        ai_response: log.ai_response.truncate(100),
        tools_used: log.tool_results_json.present?
      }
    end

    # Memories created
    conversation.conversation_memories.each do |memory|
      events << {
        type: "memory_created",
        timestamp: memory.created_at,
        title: "Memory Created",
        details: "#{memory.memory_type}: #{memory.summary.truncate(60)}"
      }
    end

    # Conversation end
    if conversation.ended_at
      events << {
        type: "conversation_end",
        timestamp: conversation.ended_at,
        title: "Conversation Ended",
        details: "Duration: #{conversation.duration&.round(2)}s"
      }
    end

    events.sort_by { |e| e[:timestamp] }
  end

  def extract_detailed_tools(conversation)
    all_tools = []
    conversation.conversation_logs.each do |log|
      tool_results = log.tool_results_json
      if tool_results.present?
        tool_results.each do |tool_name, result|
          all_tools << {
            log_id: log.id,
            timestamp: log.created_at,
            tool_name: tool_name,
            result: result,
            user_context: log.user_message.truncate(50)
          }
        end
      end
    end
    all_tools
  end
end
