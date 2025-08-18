# frozen_string_literal: true

# Service for collecting and analyzing tool execution timing metrics
# Uses Rails.cache for storage (no Redis dependency)
# Provides data-driven sync/async decision making
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
      daily_key = "tool_metrics:daily:#{tool_name}:#{Date.current}"
      daily_metrics = Rails.cache.fetch(daily_key, expires_in: CACHE_TTL) { [] }
      daily_metrics << duration_ms.round(2)
      Rails.cache.write(daily_key, daily_metrics, expires_in: CACHE_TTL)

      Rails.logger.info "📊 Tool metrics recorded: #{tool_name} took #{duration_ms.round(2)}ms"
    rescue StandardError => e
      Rails.logger.error "Failed to record tool metrics: #{e.message}"
    end

    # Get statistics for a tool
    def stats_for(tool_name, days: 1)
      daily_keys = (0...days).map do |day_offset|
        date = Date.current - day_offset.days
        "tool_metrics:daily:#{tool_name}:#{date}"
      end

      all_timings = daily_keys.flat_map do |key|
        Rails.cache.read(key) || []
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
      stats = stats_for(tool_name, days: days)
      return :unknown if stats[:count] == 0
      stats[:recommendation]
    end

    # Get all tools with timing data
    def all_tool_stats(days: 1)
      tool_names = []

      # Find all tool names from cache keys
      # Note: This implementation depends on cache store type
      if Rails.cache.respond_to?(:redis)
        # Redis cache store
        keys = Rails.cache.redis.keys("tool_metrics:daily:*")
        keys.each do |key|
          tool_name = key.split(":")[2]
          tool_names << tool_name if tool_name
        end
      else
        # Memory/File cache store - use instance variable (less reliable)
        cache_data = Rails.cache.instance_variable_get(:@data) || {}
        cache_data.keys.each do |key|
          if key.to_s.start_with?("tool_metrics:daily:")
            tool_name = key.to_s.split(":")[2]
            tool_names << tool_name if tool_name
          end
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
      if Rails.cache.respond_to?(:redis)
        Rails.cache.redis.del(Rails.cache.redis.keys("tool_metrics:*"))
      else
        cache_data = Rails.cache.instance_variable_get(:@data)
        return unless cache_data

        keys_to_delete = cache_data.keys.select { |key| key.to_s.start_with?("tool_metrics:") }
        keys_to_delete.each { |key| Rails.cache.delete(key) }
      end

      Rails.logger.info "🧹 All tool metrics cleared"
    end

    # Get a summary of all metrics
    def summary(days: 1)
      all_stats = all_tool_stats(days: days)
      return { total_tools: 0, recommendations: {} } if all_stats.empty?

      recommendations = all_stats.group_by { |stats| stats[:recommendation] }
      total_calls = all_stats.sum { |stats| stats[:count] }

      {
        total_tools: all_stats.length,
        total_calls: total_calls,
        days_analyzed: days,
        recommendations: {
          sync: (recommendations[:sync] || []).length,
          maybe_sync: (recommendations[:maybe_sync] || []).length,
          async: (recommendations[:async] || []).length,
          unknown: (recommendations[:unknown] || []).length
        },
        slowest_tool: all_stats.max_by { |stats| stats[:p95] },
        fastest_tool: all_stats.min_by { |stats| stats[:p95] }
      }
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
