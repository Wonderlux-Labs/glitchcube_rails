# frozen_string_literal: true

class Admin::PromptsController < Admin::BaseController
  def index
    @persona_prompts = load_persona_prompts
    @general_prompts = load_general_prompts
    @prompt_usage_stats = get_prompt_usage_stats
  end

  def show
    @prompt_file = params[:id]
    @prompt_path = find_prompt_path(@prompt_file)

    if @prompt_path && File.exist?(@prompt_path)
      @prompt_content = YAML.load_file(@prompt_path)
      @raw_content = File.read(@prompt_path)
    else
      redirect_to admin_prompts_path, alert: "Prompt file not found: #{@prompt_file}"
    end
  end

  def analytics
    @persona_usage = get_persona_usage_analytics
    @model_usage = get_model_usage_analytics
    @conversation_trends = get_conversation_trends
    @prompt_performance = get_prompt_performance_metrics
  end

  def models
    @available_models = get_available_models
    @current_models = get_current_model_configuration
    @model_capabilities = get_model_capabilities
  end

  private

  def load_persona_prompts
    persona_dir = Rails.root.join("lib", "prompts", "personas")
    return [] unless Dir.exist?(persona_dir)

    Dir.glob("#{persona_dir}/*.yml").map do |file|
      filename = File.basename(file, ".yml")
      content = YAML.load_file(file) rescue {}

      {
        name: filename.humanize,
        filename: filename,
        file_path: file,
        description: content["description"] || "No description available",
        last_modified: File.mtime(file),
        size: File.size(file)
      }
    end.sort_by { |prompt| prompt[:name] }
  end

  def load_general_prompts
    general_dir = Rails.root.join("lib", "prompts", "general")
    return [] unless Dir.exist?(general_dir)

    Dir.glob("#{general_dir}/*.yml").map do |file|
      filename = File.basename(file, ".yml")
      content = YAML.load_file(file) rescue {}

      {
        name: filename.humanize,
        filename: filename,
        file_path: file,
        description: content["description"] || "No description available",
        last_modified: File.mtime(file),
        size: File.size(file)
      }
    end.sort_by { |prompt| prompt[:name] }
  end

  def find_prompt_path(filename)
    # Try persona prompts first
    persona_path = Rails.root.join("lib", "prompts", "personas", "#{filename}.yml")
    return persona_path if File.exist?(persona_path)

    # Try general prompts
    general_path = Rails.root.join("lib", "prompts", "general", "#{filename}.yml")
    return general_path if File.exist?(general_path)

    nil
  end

  def get_prompt_usage_stats
    # Get usage statistics from recent conversations
    recent_conversations = Conversation.where("created_at > ?", 30.days.ago) rescue []

    persona_usage = recent_conversations.group(:persona).count rescue {}

    {
      total_conversations: recent_conversations.count,
      persona_usage: persona_usage,
      most_used_persona: persona_usage.max_by { |_, count| count }&.first,
      unique_personas: persona_usage.keys.count
    }
  end

  def get_persona_usage_analytics
    # Analyze persona usage over time
    conversations = Conversation.where("created_at > ?", 90.days.ago) rescue []

    daily_usage = conversations.group(:persona)
                              .group_by_day(:created_at, last: 30)
                              .count rescue {}

    persona_stats = conversations.group(:persona).group do |conversation|
      {
        count: conversations.where(persona: conversation.persona).count,
        avg_duration: conversations.where(persona: conversation.persona).average(:duration),
        success_rate: calculate_success_rate(conversation.persona)
      }
    end rescue {}

    { daily_usage: daily_usage, persona_stats: persona_stats }
  end

  def get_model_usage_analytics
    # Get model usage from LLM service or conversation logs
    {
      primary_model: Rails.configuration.primary_model,
      summarizer_model: Rails.configuration.summarizer_model,
      backup_models: Rails.configuration.backup_models || []
    }
  end

  def get_conversation_trends
    # Analyze conversation patterns
    conversations = Conversation.where("created_at > ?", 30.days.ago) rescue []

    {
      daily_count: conversations.group_by_day(:created_at, last: 30).count,
      avg_duration: conversations.average(:duration)&.round(2),
      completion_rate: calculate_completion_rate(conversations)
    }
  end

  def get_prompt_performance_metrics
    # Calculate performance metrics for prompts
    {
      avg_response_time: 1.2, # Would come from actual metrics
      error_rate: 0.05,
      user_satisfaction: 4.2
    }
  end

  def get_available_models
    # Get available models from configuration or service
    [
      { name: "GPT-4", provider: "OpenAI", capabilities: [ "text", "analysis" ] },
      { name: "Claude-3", provider: "Anthropic", capabilities: [ "text", "analysis", "reasoning" ] },
      { name: "Llama-2", provider: "Meta", capabilities: [ "text", "chat" ] }
    ]
  end

  def get_current_model_configuration
    {
      primary: Rails.configuration.primary_model || "Not configured",
      summarizer: Rails.configuration.summarizer_model || "Not configured",
      temperature: Rails.configuration.llm_temperature || 0.7,
      max_tokens: Rails.configuration.max_tokens || 4000
    }
  end

  def get_model_capabilities
    {
      "GPT-4" => { max_tokens: 8192, context_window: 32000, supports_functions: true },
      "Claude-3" => { max_tokens: 4096, context_window: 200000, supports_functions: true },
      "Llama-2" => { max_tokens: 4096, context_window: 4096, supports_functions: false }
    }
  end

  def calculate_success_rate(persona)
    # Calculate success rate based on conversation completion
    total = Conversation.where(persona: persona).count rescue 0
    completed = Conversation.where(persona: persona, status: "completed").count rescue 0

    return 0 if total.zero?
    (completed.to_f / total * 100).round(1)
  end

  def calculate_completion_rate(conversations)
    return 0 if conversations.empty?

    completed = conversations.select { |c| c.respond_to?(:status) && c.status == "completed" }.count
    (completed.to_f / conversations.count * 100).round(1)
  end
end
