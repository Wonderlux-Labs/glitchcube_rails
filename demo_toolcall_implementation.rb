#!/usr/bin/env ruby
# Demo script showing ValidatedToolCall objects and ToolMetrics in action

puts "🚀 ToolCall Implementation Demo"
puts "=" * 50

# Clear any existing metrics
ToolMetrics.clear_all_metrics!

# 1. Demo ValidatedToolCall wrapper
puts "\n1. Creating ValidatedToolCall objects..."

# Create a sample tool call
tool_call_data = {
  "id" => "call_demo_123",
  "type" => "function",
  "function" => {
    "name" => "set_light_state",
    "arguments" => '{"entity_id": "light.cube_inner", "brightness": 80, "rgb_color": [255, 0, 0]}'
  }
}

openrouter_call = OpenRouter::ToolCall.new(tool_call_data)
puts "✅ Created OpenRouter::ToolCall: #{openrouter_call.name}"

# Get tool definition (simplified mock for demo)
mock_tool_definition = Struct.new(:validation_blocks).new([
  proc do |params, errors|
    if params["brightness"] && params["brightness"] < 10
      errors << "Brightness too low for visibility"
    end
    if params["rgb_color"] == [ 0, 0, 0 ]
      errors << "RGB [0, 0, 0] is black (no light). Did you mean state: 'off'?"
    end
  end
])

validated_call = ValidatedToolCall.new(openrouter_call, mock_tool_definition)
puts "✅ Created ValidatedToolCall with custom validation"

# Test validation
puts "\nValidation results:"
puts "  Valid? #{validated_call.valid?}"
puts "  Errors: #{validated_call.validation_errors}"

# Demo invalid tool call
invalid_data = tool_call_data.dup
invalid_data["function"]["arguments"] = '{"entity_id": "light.cube_inner", "brightness": 5, "rgb_color": [0, 0, 0]}'
invalid_call = ValidatedToolCall.new(OpenRouter::ToolCall.new(invalid_data), mock_tool_definition)

puts "\nInvalid tool call validation:"
puts "  Valid? #{invalid_call.valid?}"
puts "  Errors: #{invalid_call.validation_errors}"

# 2. Demo ToolMetrics service
puts "\n2. Testing ToolMetrics service..."

# Record some sample timings
tools_data = [
  { name: 'get_light_state', timings: [ 25, 30, 28, 22, 35 ] },
  { name: 'set_light_state', timings: [ 180, 200, 165, 210, 175 ] },
  { name: 'slow_operation', timings: [ 800, 900, 850, 920, 780 ] }
]

tools_data.each do |tool_info|
  tool_info[:timings].each do |timing|
    ToolMetrics.record(
      tool_name: tool_info[:name],
      duration_ms: timing,
      success: true
    )
  end
  puts "✅ Recorded #{tool_info[:timings].length} metrics for #{tool_info[:name]}"
end

# Show stats
puts "\nTool Statistics:"
tools_data.each do |tool_info|
  stats = ToolMetrics.stats_for(tool_info[:name])
  puts "  #{tool_info[:name]}:"
  puts "    P95: #{stats[:p95]}ms"
  puts "    Recommendation: #{stats[:recommendation]}"
  puts "    Burning Man P95: #{ToolMetrics.burning_man_adjusted_timing(stats[:p95])}ms"
end

# Show summary
puts "\n3. System Summary:"
summary = ToolMetrics.summary
puts "  Total tools: #{summary[:total_tools]}"
puts "  Total calls: #{summary[:total_calls]}"
puts "  Sync tools: #{summary[:recommendations][:sync]}"
puts "  Maybe-sync tools: #{summary[:recommendations][:maybe_sync]}"
puts "  Async tools: #{summary[:recommendations][:async]}"

# 4. Demo light tools validation
puts "\n4. Testing Light Tools Validation..."

# Test enhanced get_state tool
get_state_tool = Tools::Lights::GetState.definition

# Valid call
valid_get_call_data = {
  "id" => "call_get_valid",
  "type" => "function",
  "function" => {
    "name" => "get_light_state",
    "arguments" => '{"entity_id": "light.cube_inner"}'
  }
}
valid_get_call = ValidatedToolCall.new(OpenRouter::ToolCall.new(valid_get_call_data), get_state_tool)
puts "✅ Valid get_state call: #{valid_get_call.valid?}"

# Invalid call with bad entity
invalid_get_call_data = {
  "id" => "call_get_invalid",
  "type" => "function",
  "function" => {
    "name" => "get_light_state",
    "arguments" => '{"entity_id": "light.invalid_entity"}'
  }
}
invalid_get_call = ValidatedToolCall.new(OpenRouter::ToolCall.new(invalid_get_call_data), get_state_tool)
puts "❌ Invalid get_state call: #{invalid_get_call.valid?}"
puts "   Error: #{invalid_get_call.validation_errors.first}"

# Test unified set_state tool
set_state_tool = Tools::Lights::SetState.definition

# Invalid RGB color
bad_rgb_call_data = {
  "id" => "call_bad_rgb",
  "type" => "function",
  "function" => {
    "name" => "set_light_state",
    "arguments" => '{"entity_id": "light.cube_inner", "rgb_color": [256, 0, 0]}'
  }
}
bad_rgb_call = ValidatedToolCall.new(OpenRouter::ToolCall.new(bad_rgb_call_data), set_state_tool)
puts "❌ Invalid RGB color call: #{bad_rgb_call.valid?}"
puts "   Error: #{bad_rgb_call.validation_errors.first}"

puts "\n🎉 Demo complete! The ToolCall implementation is working:"
puts "   ✅ ValidatedToolCall wrapper adds validation to OpenRouter objects"
puts "   ✅ ToolMetrics service collects timing data using Rails.cache"
puts "   ✅ Custom validation provides helpful error messages"
puts "   ✅ Burning Man network adjustments calculated"
puts "   ✅ Light tools consolidated with enhanced validation"

puts "\nNext steps:"
puts "   • Run rake tools:analyze_timing for detailed analysis"
puts "   • Run rake tools:burning_man_report for network impact"
puts "   • Integration with ToolExecutor provides automatic timing"
