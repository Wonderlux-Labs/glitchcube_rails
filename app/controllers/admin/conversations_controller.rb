# app/controllers/admin/conversations_controller.rb

class Admin::ConversationsController < Admin::BaseController
  def index
    @conversations = Conversation.includes(:conversation_logs)
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

    @personas = Persona.active.order(:name)
  end

  def show
    @conversation = Conversation.find(params[:id])
    @logs = @conversation.conversation_logs.chronological
    @timeline = build_timeline(@conversation, @logs)
  end

  private

  # One timestamp-ordered timeline mixing each conversation turn with the HASS
  # action-agent's results for that conversation (stored on the Conversation,
  # not per-turn — see EnvironmentDirectorJob#store_results). Best-effort
  # ordering only: this is a dev/debug view, not an exact causal trace.
  def build_timeline(conversation, logs)
    events = logs.map { |log| { type: :turn, timestamp: log.created_at, log: log } }

    Array(conversation.metadata_json["pending_ha_results"]).each do |result|
      timestamp = result["timestamp"].present? ? Time.zone.parse(result["timestamp"]) : conversation.started_at
      events << { type: :action_result, timestamp: timestamp, result: result }
    end

    events.sort_by { |e| e[:timestamp] || Time.zone.at(0) }
  end
end
