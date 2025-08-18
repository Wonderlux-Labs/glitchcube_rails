# Two-tier tool architecture configuration
Rails.application.configure do
  # Enable two-tier tools mode (narrative LLM + technical LLM)
  config.two_tier_tools_enabled = ENV['TWO_TIER_TOOLS'] == 'true'
  
  # Tool-calling LLM model (defaults to default_ai_model if not set)
  config.tool_calling_model = ENV['TOOL_CALLING_MODEL'] || 'mistralai/mistral-small-3.2-24b-instruct'
end