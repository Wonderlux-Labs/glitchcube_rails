# OpenRouter ToolCall Objects Implementation Plan

## Overview

This document outlines the complete implementation plan for adopting OpenRouter's ToolCall objects and DSL throughout the two-tier LLM architecture, with comprehensive timing metrics using Rails.cache for data-driven sync/async optimization.

## Current State Analysis

### Pain Points to Address
1. **Manual Type Checking**: Code like `tool_call.respond_to?(:name) ? tool_call.name : tool_call['name']`
2. **No Validation**: No pre-execution validation of tool arguments
3. **ActiveJob Serialization Issues**: `_aj_symbol_keys` causing deserialization problems
4. **No Timing Data**: Cannot make informed sync/async decisions
5. **Network Latency Blind**: No consideration for Burning Man network conditions

### Benefits of ToolCall Objects
- Built-in validation with `.valid?` and `.validation_errors`
- Type safety and argument checking
- Clean serialization with `.to_result_message`
- Consistent interface across all tools
- **Custom validation with helpful error messages**
- **Entity-specific validation and suggestions**
- **Live system state validation**

## Architecture Components

### 1. ToolMetrics Service

Uses Rails.cache for timing data storage and analysis.

```ruby
# app/services/tool_metrics.rb
class ToolMetrics
  # Timing thresholds in milliseconds
  SYNC_THRESHOLD_MS = 100
  MAYBE_SYNC_THRESHOLD_MS = 500
  BURNING_MAN_OVERHEAD_MS = 300
  
  # Cache TTL: 7 days
  CACHE_TTL = 7.days
  
  class << self
    # Record tool execution timing
    def record(tool_name:, duration_ms:, success:, entity_id: nil)
      timestamp = Time.current.to_i
      cache_key = "tool_metrics:#{tool_name}:#{timestamp}"
      
      metric_data = {
        tool_name: tool_name,
        duration_ms: duration_ms.round(2),
        success: success,
        entity_id: entity_id,
        timestamp: timestamp
      }
      
      Rails.cache.write(cache_key, metric_data, expires_in: CACHE_TTL)
      
      # Also append to daily aggregation for faster analysis
      daily_key = "tool_metrics:daily:#{tool_name}:#{Date.current.to_s}"
      daily_metrics = Rails.cache.fetch(daily_key, expires_in: CACHE_TTL) { [] }
      daily_metrics << duration_ms.round(2)
      Rails.cache.write(daily_key, daily_metrics, expires_in: CACHE_TTL)
      
      Rails.logger.info "📊 Tool metrics recorded: #{tool_name} took #{duration_ms.round(2)}ms"
    end
    
    # Get statistics for a tool
    def stats_for(tool_name, days: 1)
      daily_keys = (0...days).map do |day_offset|
        date = Date.current - day_offset.days
        "tool_metrics:daily:#{tool_name}:#{date}"
      end
      
      all_timings = daily_keys.flat_map do |key|
        Rails.cache.fetch(key) { [] }
      end
      
      return empty_stats(tool_name) if all_timings.empty?
      
      sorted_timings = all_timings.sort
      count = sorted_timings.length
      
      {
        tool_name: tool_name,
        count: count,
        p50: percentile(sorted_timings, 50),
        p95: percentile(sorted_timings, 95),
        p99: percentile(sorted_timings, 99),
        avg: (sorted_timings.sum / count.to_f).round(2),
        min: sorted_timings.first,
        max: sorted_timings.last,
        recommendation: recommendation_for_timings(sorted_timings)
      }
    end
    
    # Get recommendation for sync/async based on timings
    def recommendation_for(tool_name, days: 1)
      stats = stats_for(tool_name, days)
      return :unknown if stats[:count] == 0
      stats[:recommendation]
    end
    
    # Get all tools with timing data
    def all_tool_stats(days: 1)
      tool_names = []
      
      # Find all tool names from cache keys
      Rails.cache.instance_variable_get(:@data)&.keys&.each do |key|
        if key.to_s.start_with?("tool_metrics:daily:")
          tool_name = key.to_s.split(":")[2]
          tool_names << tool_name if tool_name
        end
      end
      
      tool_names.uniq.map { |name| stats_for(name, days: days) }
    end
    
    # Adjust timing for Burning Man network conditions
    def burning_man_adjusted_timing(base_timing_ms)
      base_timing_ms + BURNING_MAN_OVERHEAD_MS
    end
    
    # Clear all metrics (for testing)
    def clear_all_metrics!
      Rails.cache.instance_variable_get(:@data)&.keys&.each do |key|
        Rails.cache.delete(key) if key.to_s.start_with?("tool_metrics:")
      end
    end
    
    private
    
    def percentile(sorted_array, percentile)
      return 0 if sorted_array.empty?
      
      index = (percentile / 100.0) * (sorted_array.length - 1)
      lower_index = index.floor
      upper_index = index.ceil
      
      if lower_index == upper_index
        sorted_array[lower_index].round(2)
      else
        lower_value = sorted_array[lower_index]
        upper_value = sorted_array[upper_index]
        weight = index - lower_index
        (lower_value + weight * (upper_value - lower_value)).round(2)
      end
    end
    
    def recommendation_for_timings(sorted_timings)
      p95 = percentile(sorted_timings, 95)
      adjusted_p95 = burning_man_adjusted_timing(p95)
      
      if adjusted_p95 < SYNC_THRESHOLD_MS
        :sync
      elsif adjusted_p95 < MAYBE_SYNC_THRESHOLD_MS
        :maybe_sync
      else
        :async
      end
    end
    
    def empty_stats(tool_name)
      {
        tool_name: tool_name,
        count: 0,
        p50: 0,
        p95: 0,
        p99: 0,
        avg: 0,
        min: 0,
        max: 0,
        recommendation: :unknown
      }
    end
  end
end
```

### 2. Enhanced ToolExecutor

Replaces manual type checking with ToolCall validation and adds timing.

```ruby
# Modifications to app/services/tool_executor.rb
class ToolExecutor
  def execute_sync(tool_calls)
    return {} if tool_calls.blank?
    
    results = {}
    
    tool_calls.each do |tool_call|
      # Ensure we have a ToolCall object
      unless tool_call.is_a?(OpenRouter::ToolCall)
        Rails.logger.error "❌ Expected ToolCall object, got #{tool_call.class}"
        results[tool_call.name] = {
          error: "Invalid tool call object type",
          success: false
        }
        next
      end
      
      # Validate ToolCall before execution
      unless tool_call.valid?
        Rails.logger.warn "⚠️ Tool call validation failed: #{tool_call.name}"
        results[tool_call.name] = tool_call.to_result_message({
          error: "Validation failed",
          details: tool_call.validation_errors,
          success: false
        })
        
        # Record failed validation as 0ms (immediate failure)
        ToolMetrics.record(
          tool_name: tool_call.name,
          duration_ms: 0,
          success: false
        )
        next
      end
      
      # Execute with timing
      result = execute_with_timing(tool_call)
      results[tool_call.name] = tool_call.to_result_message(result)
    end
    
    results
  end
  
  private
  
  def execute_with_timing(tool_call)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    
    begin
      # Execute the actual tool
      result = Tools::Registry.execute_tool(
        tool_call.name, 
        **tool_call.arguments.symbolize_keys
      )
      
      duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time
      success = result[:success] != false # Default to true unless explicitly false
      
      # Record metrics
      ToolMetrics.record(
        tool_name: tool_call.name,
        duration_ms: duration_ms,
        success: success,
        entity_id: tool_call.arguments['entity_id']
      )
      
      result
      
    rescue StandardError => e
      duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time
      
      # Record failed execution
      ToolMetrics.record(
        tool_name: tool_call.name,
        duration_ms: duration_ms,
        success: false
      )
      
      Rails.logger.error "❌ Tool execution failed: #{tool_call.name} - #{e.message}"
      
      {
        success: false,
        error: e.message,
        tool: tool_call.name
      }
    end
  end
end
```

### 3. Fixed AsyncToolJob

Proper serialization/deserialization of ToolCall objects.

```ruby
# Modifications to app/jobs/async_tool_job.rb
class AsyncToolJob < ApplicationJob
  queue_as :default
  
  # Updated method signature to accept ToolCall objects
  def perform(tool_call_data, session_id = nil, conversation_id = nil)
    # Deserialize ToolCall object
    tool_call = deserialize_tool_call(tool_call_data)
    
    # Validate before execution
    unless tool_call.valid?
      Rails.logger.error "❌ AsyncToolJob: Invalid ToolCall - #{tool_call.validation_errors}"
      
      # Record validation failure
      ToolMetrics.record(
        tool_name: tool_call.name,
        duration_ms: 0,
        success: false
      )
      return
    end
    
    # Execute with timing
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
    
    begin
      result = Tools::Registry.execute_tool(
        tool_call.name,
        **tool_call.arguments.symbolize_keys
      )
      
      duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time
      success = result[:success] != false
      
      # Record metrics
      ToolMetrics.record(
        tool_name: tool_call.name,
        duration_ms: duration_ms,
        success: success,
        entity_id: tool_call.arguments['entity_id']
      )
      
      Rails.logger.info "✅ AsyncToolJob completed: #{tool_call.name} in #{duration_ms.round(2)}ms"
      
    rescue StandardError => e
      duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time
      
      # Record failure
      ToolMetrics.record(
        tool_name: tool_call.name,
        duration_ms: duration_ms,
        success: false
      )
      
      Rails.logger.error "❌ AsyncToolJob failed: #{tool_call.name} - #{e.message}"
    end
  end
  
  # Class method to enqueue ToolCall objects
  def self.enqueue_tool_call(tool_call, session_id: nil, conversation_id: nil)
    serialized_tool_call = serialize_tool_call(tool_call)
    perform_later(serialized_tool_call, session_id, conversation_id)
  end
  
  private
  
  def self.serialize_tool_call(tool_call)
    {
      name: tool_call.name,
      arguments: tool_call.arguments
    }
  end
  
  def deserialize_tool_call(tool_call_data)
    # Clean ActiveJob symbol key artifacts
    clean_data = clean_activejob_keys(tool_call_data)
    
    OpenRouter::ToolCall.new(
      name: clean_data['name'] || clean_data[:name],
      arguments: clean_data['arguments'] || clean_data[:arguments] || {}
    )
  end
  
  def clean_activejob_keys(data)
    case data
    when Hash
      data.reject { |k, v| k == '_aj_symbol_keys' }.transform_values { |v| clean_activejob_keys(v) }
    when Array
      data.map { |item| clean_activejob_keys(item) }
    else
      data
    end
  end
end
```

### 4. Analysis Rake Tasks

Tasks for analyzing timing data and making recommendations.

```ruby
# lib/tasks/tool_metrics.rake
namespace :tools do
  desc "Analyze tool execution timing and provide sync/async recommendations"
  task analyze_timing: :environment do
    puts "\n" + "="*80
    puts "TOOL EXECUTION TIMING ANALYSIS"
    puts "="*80
    
    all_stats = ToolMetrics.all_tool_stats(days: 7)
    
    if all_stats.empty?
      puts "\nNo timing data available. Run some tools first!"
      exit
    end
    
    # Group by recommendation
    recommendations = all_stats.group_by { |stats| stats[:recommendation] }
    
    %i[sync maybe_sync async unknown].each do |category|
      tools_in_category = recommendations[category] || []
      next if tools_in_category.empty?
      
      puts "\n#{category.to_s.upcase} TOOLS (#{tools_in_category.length}):"
      puts "-" * 40
      
      tools_in_category.sort_by { |stats| stats[:p95] }.each do |stats|
        puts sprintf("%-30s | %3d calls | P50:%6.1fms | P95:%6.1fms | P99:%6.1fms", 
                    stats[:tool_name], 
                    stats[:count],
                    stats[:p50], 
                    stats[:p95], 
                    stats[:p99])
      end
    end
    
    # Burning Man analysis
    puts "\n" + "="*80
    puts "BURNING MAN NETWORK ANALYSIS (+300ms overhead)"
    puts "="*80
    
    all_stats.each do |stats|
      next if stats[:count] == 0
      
      adjusted_p95 = ToolMetrics.burning_man_adjusted_timing(stats[:p95])
      current_rec = stats[:recommendation]
      
      # Determine if recommendation changes with Burning Man conditions
      burning_man_rec = if adjusted_p95 < ToolMetrics::SYNC_THRESHOLD_MS
                          :sync
                        elsif adjusted_p95 < ToolMetrics::MAYBE_SYNC_THRESHOLD_MS
                          :maybe_sync
                        else
                          :async
                        end
      
      if current_rec != burning_man_rec
        puts sprintf("%-30s | %s -> %s (P95: %.1fms -> %.1fms)", 
                    stats[:tool_name],
                    current_rec.to_s.upcase,
                    burning_man_rec.to_s.upcase,
                    stats[:p95],
                    adjusted_p95)
      end
    end
    
    puts "\nThresholds:"
    puts "  SYNC: < 100ms"
    puts "  MAYBE_SYNC: 100-500ms"
    puts "  ASYNC: > 500ms"
    puts "  Burning Man overhead: +300ms"
  end
  
  desc "Generate Burning Man worst-case timing report"
  task burning_man_report: :environment do
    puts "\n" + "="*80
    puts "BURNING MAN WORST-CASE TIMING REPORT"
    puts "="*80
    puts "Assumes +300ms network overhead on all operations"
    
    all_stats = ToolMetrics.all_tool_stats(days: 7)
    
    if all_stats.empty?
      puts "\nNo timing data available. Run some tools first!"
      exit
    end
    
    # Sort by worst-case P99 timing
    worst_case_tools = all_stats.map do |stats|
      stats.merge(
        burning_man_p95: ToolMetrics.burning_man_adjusted_timing(stats[:p95]),
        burning_man_p99: ToolMetrics.burning_man_adjusted_timing(stats[:p99])
      )
    end.sort_by { |stats| stats[:burning_man_p99] }.reverse
    
    puts "\nWORST-CASE SCENARIOS (P99 + 300ms):"
    puts "-" * 60
    worst_case_tools.first(10).each do |stats|
      puts sprintf("%-25s | P99: %6.1fms -> %6.1fms | %s", 
                  stats[:tool_name],
                  stats[:p99],
                  stats[:burning_man_p99],
                  stats[:recommendation].to_s.upcase)
    end
    
    puts "\nRECOMMENDATIONS:"
    puts "-" * 40
    puts "Tools taking >2000ms even in ideal conditions should be async"
    puts "Tools taking >1000ms at Burning Man should be async"
    puts "Tools taking <200ms at Burning Man can remain sync"
    
    # Find tools that might need reclassification
    needs_reclassification = worst_case_tools.select do |stats|
      stats[:burning_man_p95] > 1000 && stats[:recommendation] != :async
    end
    
    if needs_reclassification.any?
      puts "\nTOOLS THAT SHOULD BE ASYNC AT BURNING MAN:"
      needs_reclassification.each do |stats|
        puts "  - #{stats[:tool_name]} (#{stats[:burning_man_p95].round}ms P95)"
      end
    end
  end
  
  desc "Export timing data to CSV for analysis"
  task :export_csv, [:filename] => :environment do |t, args|
    filename = args[:filename] || "tool_metrics_#{Date.current}.csv"
    
    all_stats = ToolMetrics.all_tool_stats(days: 30)
    
    require 'csv'
    CSV.open(filename, "w") do |csv|
      csv << %w[tool_name count p50 p95 p99 avg min max recommendation]
      
      all_stats.each do |stats|
        csv << [
          stats[:tool_name],
          stats[:count],
          stats[:p50],
          stats[:p95],
          stats[:p99],
          stats[:avg],
          stats[:min],
          stats[:max],
          stats[:recommendation]
        ]
      end
    end
    
    puts "Exported timing data to #{filename}"
    puts "#{all_stats.length} tools included"
  end
  
  desc "Clear all timing metrics (use with caution)"
  task clear_metrics: :environment do
    print "Are you sure you want to clear all timing metrics? (y/N): "
    confirmation = STDIN.gets.chomp
    
    if confirmation.downcase == 'y'
      ToolMetrics.clear_all_metrics!
      puts "All timing metrics cleared."
    else
      puts "Operation cancelled."
    end
  end
end
```

## Implementation Steps

### Phase 1: Foundation (30 minutes)
1. **Create ToolMetrics Service**
   - [ ] Create `app/services/tool_metrics.rb`
   - [ ] Implement Rails.cache storage patterns
   - [ ] Add percentile calculations
   - [ ] Test basic recording and retrieval

### Phase 2: Integration (45 minutes)
2. **Update ToolExecutor**
   - [ ] Replace manual type checking with ToolCall validation
   - [ ] Add timing wrapper with Process::CLOCK_MONOTONIC
   - [ ] Integrate ToolMetrics recording
   - [ ] Use to_result_message for responses
   - [ ] Test with real Home Assistant calls

### Phase 3: Background Jobs (20 minutes)
3. **Fix AsyncToolJob**
   - [ ] Add serialize_tool_call method
   - [ ] Implement deserialize_tool_call with cleanup
   - [ ] Add validation before execution
   - [ ] Include timing metrics collection
   - [ ] Test background job processing

### Phase 4: Analysis Tools (15 minutes)
4. **Create Rake Tasks**
   - [ ] Create `lib/tasks/tool_metrics.rake`
   - [ ] Implement analyze_timing task
   - [ ] Implement burning_man_report task
   - [ ] Add CSV export functionality
   - [ ] Test with sample data

### Phase 5: Testing (30 minutes)
5. **Integration Testing**
   - [ ] Test full two-tier flow with timing
   - [ ] Verify Rails.cache storage and retrieval
   - [ ] Check timing precision and accuracy
   - [ ] Validate sync/async recommendations
   - [ ] Test serialization edge cases

### Phase 6: Deploy (20 minutes)
6. **Deploy and Monitor**
   - [ ] Deploy to staging environment
   - [ ] Run live timing collection
   - [ ] Execute rake tasks for analysis
   - [ ] Monitor Rails.cache memory usage
   - [ ] Adjust thresholds based on real data

## Migration from Current Code

### Before (Manual Type Checking)
```ruby
def execute_sync_tools(sync_tools)
  sync_tools.each do |tool_call|
    tool_name = tool_call.respond_to?(:name) ? tool_call.name : tool_call['name']
    arguments = tool_call.respond_to?(:arguments) ? tool_call.arguments : tool_call['arguments']
    
    result = Tools::Registry.execute_tool(tool_name, **arguments.symbolize_keys)
    results[tool_name] = result
  end
end
```

### After (ToolCall Objects)
```ruby
def execute_sync(tool_calls)
  tool_calls.each do |tool_call|
    unless tool_call.valid?
      results[tool_call.name] = tool_call.to_result_message({
        error: "Validation failed",
        details: tool_call.validation_errors
      })
      next
    end
    
    result = execute_with_timing(tool_call)
    results[tool_call.name] = tool_call.to_result_message(result)
  end
end
```

## Custom Validation System

### Enhanced Error Messages

One of the biggest benefits of ToolCall objects is the ability to provide sophisticated, helpful error messages that guide users toward correct usage.

#### Before (Generic validation)
```ruby
def validate_entity(entity_id, domain: nil)
  # Basic check if entity exists
  return { error: "Entity 'light.wrong' not found" }
end
```

#### After (Custom ToolCall validation)
```ruby
class Tools::Lights::SetState < Tools::BaseTool
  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "light_set_state"
      description "Unified control for cube lights"
      
      parameters do
        string :entity_id, required: true,
               description: "Light entity to control",
               enum: -> { CUBE_LIGHT_ENTITIES }
        
        string :state, enum: %w[on off],
               description: "Turn light on or off"
        
        number :brightness, minimum: 0, maximum: 100,
               description: "Brightness percentage (0-100)"
        
        array :rgb_color,
              description: "RGB color as [R, G, B] values (0-255)"
        
        string :effect,
               description: "Light effect name"
        
        number :transition, minimum: 0, maximum: 60,
               description: "Transition time in seconds"
      end
      
      # Custom validation with helpful error messages
      validate do |params|
        errors = []
        
        # 1. Enhanced entity validation
        if params[:entity_id] && !CUBE_LIGHT_ENTITIES.include?(params[:entity_id])
          available = CUBE_LIGHT_ENTITIES.join(", ")
          errors << "Invalid light entity '#{params[:entity_id]}'. Available cube lights: #{available}"
        end
        
        # 2. RGB color validation with examples
        if params[:rgb_color]
          if !params[:rgb_color].is_a?(Array) || params[:rgb_color].length != 3
            errors << "rgb_color must be an array of 3 integers, e.g., [255, 0, 0] for red"
          elsif params[:rgb_color].any? { |c| !c.is_a?(Integer) || c < 0 || c > 255 }
            invalid_values = params[:rgb_color].select { |c| !c.is_a?(Integer) || c < 0 || c > 255 }
            errors << "rgb_color values must be integers 0-255. Invalid values: #{invalid_values}"
          end
        end
        
        # 3. Effect validation (check if effect exists for this light)
        if params[:effect] && params[:entity_id]
          available_effects = get_available_effects_for_entity(params[:entity_id])
          unless available_effects.include?(params[:effect])
            if available_effects.any?
              errors << "Effect '#{params[:effect]}' not available for #{params[:entity_id]}. Available: #{available_effects.join(', ')}"
            else
              errors << "Light #{params[:entity_id]} does not support effects"
            end
          end
        end
        
        # 4. Logical validation
        if params[:state] == 'off' && (params[:brightness] || params[:rgb_color] || params[:effect])
          errors << "Cannot set brightness, color, or effects when turning light off. Use state: 'on' instead."
        end
        
        # 5. Smart suggestions
        if params[:rgb_color] == [0, 0, 0]
          errors << "RGB [0, 0, 0] is black (no light). Did you mean to set state: 'off' instead?"
        end
        
        # 6. Live system validation
        if params[:entity_id] && !light_is_responsive?(params[:entity_id])
          errors << "Light #{params[:entity_id]} is currently unresponsive. Check if it's powered on."
        end
        
        errors
      end
    end
  end
  
  private
  
  def self.get_available_effects_for_entity(entity_id)
    # Cache effects to avoid repeated API calls during validation
    @effects_cache ||= {}
    @effects_cache[entity_id] ||= begin
      entity_data = HomeAssistantService.entity(entity_id)
      entity_data&.dig('attributes', 'effect_list') || []
    rescue
      []
    end
  end
  
  def self.light_is_responsive?(entity_id)
    # Quick ping to see if light responds
    HomeAssistantService.entity(entity_id).present?
  rescue
    false
  end
end
```

### Validation Error Examples

#### Smart Entity Validation
```ruby
# Before
❌ "Entity 'light.wrong' not found"

# After  
✅ "Invalid light entity 'light.wrong'. Available cube lights: light.cube_voice_ring, light.cube_inner, light.cube_light_top"
```

#### Helpful Parameter Validation  
```ruby
# Before
❌ "Invalid arguments"

# After
✅ "rgb_color must be an array of 3 integers, e.g., [255, 0, 0] for red"
✅ "rgb_color values must be integers 0-255. Invalid values: [256, -10]"
✅ "Effect 'sparkle' not available for light.cube_inner. Available: rainbow, pulse, strobe, fade"
```

#### Smart Logic Validation
```ruby
# Before
❌ "Tool execution failed"

# After
✅ "Cannot set brightness, color, or effects when turning light off. Use state: 'on' instead."
✅ "RGB [0, 0, 0] is black (no light). Did you mean to set state: 'off' instead?"
✅ "Light light.cube_inner is currently unresponsive. Check if it's powered on."
```

### Context-Aware Validation

The validation system can also provide context-aware suggestions:

```ruby
validate do |params|
  errors = []
  
  # Entity-specific recommendations
  if params[:entity_id] == 'light.cube_voice_ring' && params[:effect] == 'matrix'
    errors << "Voice ring doesn't support matrix effects. Try 'pulse' or 'rainbow' for voice feedback."
  end
  
  # Brightness warnings
  if params[:brightness] && params[:brightness] < 5 && params[:state] == 'on'
    errors << "Brightness #{params[:brightness]}% is very dim. Consider brightness: 20 or higher for visibility."
  end
  
  # Color accessibility
  if params[:rgb_color] == [255, 255, 255] && params[:brightness] && params[:brightness] > 80
    errors << "White at #{params[:brightness]}% brightness may be too intense. Consider brightness: 50 or a warmer color."
  end
  
  errors
end
```

### Integration with ToolExecutor

The enhanced validation integrates seamlessly with the timing system:

```ruby
def execute_with_timing(tool_call)
  start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
  
  # Validation happens first (and is timed!)
  unless tool_call.valid?
    duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) - start_time
    
    # Record validation failure
    ToolMetrics.record(
      tool_name: tool_call.name,
      duration_ms: duration_ms,
      success: false
    )
    
    # Return helpful error messages
    return {
      success: false,
      error: "Validation failed",
      details: tool_call.validation_errors, # Rich, helpful messages!
      validation_time_ms: duration_ms.round(2)
    }
  end
  
  # Continue with execution...
end
```

### Benefits of Enhanced Validation

1. **Better User Experience**: Clear, actionable error messages
2. **Faster Learning**: LLM learns correct usage patterns quickly  
3. **Fewer API Calls**: Catch errors before hitting Home Assistant
4. **Smart Suggestions**: Guide users toward correct parameters
5. **Live System Awareness**: Check actual device state
6. **Entity-Specific Logic**: Different validation per light type
7. **Performance Tracking**: Even validation errors are timed

## Rails.cache Configuration

### Development
```ruby
# config/environments/development.rb
config.cache_store = :memory_store, { size: 64.megabytes }
```

### Production
```ruby
# config/environments/production.rb
config.cache_store = :file_store, "/tmp/cache"
# or
config.cache_store = :mem_cache_store, "localhost:11211"
```

## Testing Strategy

### Unit Tests
```ruby
# spec/services/tool_metrics_spec.rb
RSpec.describe ToolMetrics do
  before { ToolMetrics.clear_all_metrics! }
  
  it "records timing with proper precision" do
    ToolMetrics.record(tool_name: "turn_on_light", duration_ms: 45.2, success: true)
    stats = ToolMetrics.stats_for("turn_on_light")
    
    expect(stats[:count]).to eq(1)
    expect(stats[:p50]).to be_within(0.1).of(45.2)
  end
  
  it "recommends sync for fast tools" do
    10.times { ToolMetrics.record(tool_name: "get_light_state", duration_ms: 50, success: true) }
    recommendation = ToolMetrics.recommendation_for("get_light_state")
    
    expect(recommendation).to eq(:sync)
  end
  
  it "handles Burning Man overhead correctly" do
    adjusted = ToolMetrics.burning_man_adjusted_timing(150)
    expect(adjusted).to eq(450) # 150 + 300
  end
end
```

### Integration Tests
```ruby
# spec/services/tool_executor_spec.rb
RSpec.describe ToolExecutor do
  it "validates ToolCall objects before execution" do
    invalid_tool_call = OpenRouter::ToolCall.new(
      name: "set_light_color_and_brightness",
      arguments: { rgb_color: [256, 0, 0] } # Invalid: > 255
    )
    
    executor = ToolExecutor.new
    result = executor.execute_sync([invalid_tool_call])
    
    expect(result["set_light_color_and_brightness"][:error]).to include("Validation failed")
  end
  
  it "records timing metrics for all executions" do
    tool_call = OpenRouter::ToolCall.new(
      name: "turn_on_light",
      arguments: { entity_id: "light.cube_inner" }
    )
    
    expect { 
      ToolExecutor.new.execute_sync([tool_call]) 
    }.to change { 
      ToolMetrics.stats_for("turn_on_light")[:count] 
    }.by(1)
  end
end
```

## Rollback Strategy

### Quick Rollback (Keep Timing)
```ruby
# Comment out validation, keep timing collection
unless false # tool_call.valid?
  # Validation disabled for rollback
end
```

### Full Rollback
```bash
git stash  # Save changes
git checkout main  # Return to stable state
```

### Partial Adoption
- Use ToolCall objects only for new tools
- Gradually migrate existing tools
- Monitor metrics during transition

## Expected Improvements

### Immediate Benefits
- **Type Safety**: Catch argument errors before API calls
- **Validation**: Prevent invalid Home Assistant requests
- **Clean Code**: Remove all manual type checking patterns
- **Timing Data**: Real metrics for optimization decisions

### Burning Man Specific
- **Network Awareness**: Account for 300-500ms latency
- **Smart Routing**: Data-driven sync/async classification
- **Better UX**: Faster perceived response times
- **Reliability**: Reduced failure rate from validation

## Monitoring and Success Criteria

### Key Metrics to Track
1. **Tool Success Rate**: Should increase with validation
2. **P95 Response Times**: By tool type and network conditions
3. **Rails.cache Memory Usage**: Monitor for memory leaks
4. **ActiveJob Queue Depth**: Should remain stable
5. **Error Rate**: Should decrease significantly

### Success Criteria
- ✅ All tool calls use validated ToolCall objects
- ✅ Timing metrics collected for every execution
- ✅ AsyncToolJob properly handles ToolCall serialization
- ✅ Rake tasks provide actionable recommendations
- ✅ No manual type checking patterns remain
- ✅ Tests pass with real Home Assistant integration
- ✅ Burning Man worst-case reports available

## Sample Commands for Tomorrow

```bash
# 1. Start implementation
git checkout -b feature/toolcall-objects-with-cache-metrics

# 2. Test ToolMetrics service
rails console
> ToolMetrics.record(tool_name: "test", duration_ms: 45.2, success: true)
> ToolMetrics.stats_for("test")

# 3. Run timing analysis
rake tools:analyze_timing

# 4. Generate Burning Man report
rake tools:burning_man_report

# 5. Export data for analysis
rake tools:export_csv[metrics_analysis.csv]

# 6. Test with real Home Assistant
# (Use conversation interface to trigger tools)

# 7. Commit comprehensive changes
git add -A
git commit -m "feat: adopt OpenRouter ToolCall objects with Rails.cache timing

- Add ToolMetrics service using Rails.cache for timing data
- Migrate ToolExecutor to use ToolCall validation and timing
- Fix AsyncToolJob serialization for ToolCall objects  
- Add comprehensive rake tasks for timing analysis
- Include Burning Man network overhead calculations

Provides type safety, validation, and data-driven sync/async decisions."
```

## Notes and Considerations

### Rails.cache vs Redis
- **Pros**: No external dependency, built into Rails, automatic expiration
- **Cons**: Lost on restart (memory_store), less sophisticated than Redis
- **Mitigation**: Use file_store or memcached in production for persistence

### Memory Management
- Monitor Rails.cache size with metrics
- Set reasonable size limits in configuration  
- Use TTL to prevent unbounded growth
- Consider periodic cleanup if needed

### Performance Impact
- Rails.cache operations are fast (< 1ms typically)
- Timing collection adds ~0.1ms overhead
- Percentile calculations are done in-memory
- Cache lookups are optimized for read-heavy workloads

### Future Enhancements
- Add tool execution history visualization
- Implement alerting for performance regressions
- Add A/B testing for sync/async decisions
- Create dashboard for real-time monitoring

---

## Implementation Checklist

Print this section and check off items as you complete them:

### Pre-Implementation
- [x] Document current pain points  
- [x] Design ToolMetrics with Rails.cache
- [x] Plan ToolCall object adoption strategy
- [x] Create comprehensive implementation document

### Morning Implementation  
- [ ] Create ToolMetrics service (app/services/tool_metrics.rb)
- [ ] Update ToolExecutor with validation and timing
- [ ] Fix AsyncToolJob serialization issues
- [ ] Create analysis rake tasks (lib/tasks/tool_metrics.rake)
- [ ] Write comprehensive tests
- [ ] Test with real Home Assistant integration
- [ ] Deploy and collect initial metrics
- [ ] Run analysis and adjust thresholds
- [ ] Document findings and recommendations

### Success Validation
- [ ] All tools use ToolCall objects with validation
- [ ] Timing metrics collected and stored properly
- [ ] Rake tasks provide useful analysis
- [ ] No manual type checking remains
- [ ] System performs well at Burning Man conditions
- [ ] Team ready for art installation deployment

Ready for implementation! 🚀