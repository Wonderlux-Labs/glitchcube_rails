# frozen_string_literal: true

namespace :tools do
  desc "Analyze tool execution timing and provide sync/async recommendations"
  task analyze_timing: :environment do
    puts "\n" + "="*80
    puts "TOOL EXECUTION TIMING ANALYSIS"
    puts "="*80

    all_stats = ToolMetrics.all_tool_stats(days: 7)

    if all_stats.empty?
      puts "\nNo timing data available. Run some tools first!"
      puts "Try: rails console"
      puts "Then: ToolMetrics.record(tool_name: 'test', duration_ms: 45.2, success: true)"
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

    # Show summary
    summary = ToolMetrics.summary(days: 7)
    puts "\n" + "="*80
    puts "SUMMARY"
    puts "="*80
    puts "Total tools analyzed: #{summary[:total_tools]}"
    puts "Total calls: #{summary[:total_calls]}"
    puts "Days of data: #{summary[:days_analyzed]}"
    puts ""
    puts "Recommendations:"
    puts "  SYNC: #{summary[:recommendations][:sync]} tools"
    puts "  MAYBE_SYNC: #{summary[:recommendations][:maybe_sync]} tools"
    puts "  ASYNC: #{summary[:recommendations][:async]} tools"
    puts "  UNKNOWN: #{summary[:recommendations][:unknown]} tools"

    if summary[:slowest_tool]
      puts "\nSlowest tool: #{summary[:slowest_tool][:tool_name]} (P95: #{summary[:slowest_tool][:p95]}ms)"
    end
    if summary[:fastest_tool]
      puts "Fastest tool: #{summary[:fastest_tool][:tool_name]} (P95: #{summary[:fastest_tool][:p95]}ms)"
    end

    puts "\nThresholds:"
    puts "  SYNC: < #{ToolMetrics::SYNC_THRESHOLD_MS}ms"
    puts "  MAYBE_SYNC: #{ToolMetrics::SYNC_THRESHOLD_MS}-#{ToolMetrics::MAYBE_SYNC_THRESHOLD_MS}ms"
    puts "  ASYNC: > #{ToolMetrics::MAYBE_SYNC_THRESHOLD_MS}ms"
  end

  desc "Generate Burning Man worst-case timing report"
  task burning_man_report: :environment do
    puts "\n" + "="*80
    puts "BURNING MAN WORST-CASE TIMING REPORT"
    puts "="*80
    puts "Assumes +#{ToolMetrics::BURNING_MAN_OVERHEAD_MS}ms network overhead on all operations"

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

    puts "\nWORST-CASE SCENARIOS (P99 + #{ToolMetrics::BURNING_MAN_OVERHEAD_MS}ms):"
    puts "-" * 60
    worst_case_tools.first(10).each do |stats|
      puts sprintf("%-25s | P99: %6.1fms -> %6.1fms | %s",
                  stats[:tool_name],
                  stats[:p99],
                  stats[:burning_man_p99],
                  stats[:recommendation].to_s.upcase)
    end

    # Burning Man analysis
    puts "\n" + "="*60
    puts "BURNING MAN IMPACT ANALYSIS"
    puts "="*60

    reclassification_count = 0
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
        reclassification_count += 1
        puts sprintf("%-30s | %s -> %s (P95: %.1fms -> %.1fms)",
                    stats[:tool_name],
                    current_rec.to_s.upcase,
                    burning_man_rec.to_s.upcase,
                    stats[:p95],
                    adjusted_p95)
      end
    end

    puts "\nSUMMARY:" if reclassification_count > 0
    puts "#{reclassification_count} tools would be reclassified at Burning Man" if reclassification_count > 0
    puts "No tools would be reclassified at Burning Man" if reclassification_count == 0

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
  task :export_csv, [ :filename ] => :environment do |t, args|
    filename = args[:filename] || "tool_metrics_#{Date.current}.csv"

    all_stats = ToolMetrics.all_tool_stats(days: 30)

    if all_stats.empty?
      puts "No timing data available to export"
      exit
    end

    require "csv"
    CSV.open(filename, "w") do |csv|
      csv << %w[tool_name count p50 p95 p99 avg min max recommendation burning_man_p95]

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
          stats[:recommendation],
          ToolMetrics.burning_man_adjusted_timing(stats[:p95])
        ]
      end
    end

    puts "Exported timing data to #{filename}"
    puts "#{all_stats.length} tools included"
    puts "Data covers last 30 days"
  end

  desc "Show real-time tool metrics summary"
  task summary: :environment do
    summary = ToolMetrics.summary(days: 7)

    puts "\n📊 TOOL METRICS SUMMARY (Last 7 days)"
    puts "="*50

    if summary[:total_tools] == 0
      puts "No metrics data available yet."
      puts "\nTo start collecting metrics, run some tools through the system."
      exit
    end

    puts "🔧 Total tools: #{summary[:total_tools]}"
    puts "📞 Total calls: #{summary[:total_calls]}"
    puts ""
    puts "📈 Recommendations:"
    puts "   🚀 SYNC: #{summary[:recommendations][:sync]} tools"
    puts "   ⚡ MAYBE_SYNC: #{summary[:recommendations][:maybe_sync]} tools"
    puts "   🔄 ASYNC: #{summary[:recommendations][:async]} tools"
    puts "   ❓ UNKNOWN: #{summary[:recommendations][:unknown]} tools"

    if summary[:slowest_tool] && summary[:fastest_tool]
      puts ""
      puts "🐌 Slowest: #{summary[:slowest_tool][:tool_name]} (#{summary[:slowest_tool][:p95]}ms P95)"
      puts "🚀 Fastest: #{summary[:fastest_tool][:tool_name]} (#{summary[:fastest_tool][:p95]}ms P95)"
    end

    puts "\nRun 'rake tools:analyze_timing' for detailed analysis"
  end

  desc "Clear all timing metrics (use with caution)"
  task clear_metrics: :environment do
    print "Are you sure you want to clear all timing metrics? (y/N): "

    begin
      system("stty raw -echo")
      confirmation = STDIN.getc
    ensure
      system("stty -raw echo")
    end

    puts # newline after character input

    if confirmation.downcase == "y"
      ToolMetrics.clear_all_metrics!
      puts "✅ All timing metrics cleared."
    else
      puts "❌ Operation cancelled."
    end
  end

  desc "Test ToolMetrics with sample data"
  task sample_data: :environment do
    puts "🧪 Generating sample tool metrics data..."

    # Generate sample data for different tool types
    tools = [
      { name: "get_light_state", timings: [ 20, 25, 30, 22, 28, 35, 18, 24 ] },
      { name: "turn_on_light", timings: [ 150, 180, 200, 165, 175, 210, 145, 190 ] },
      { name: "set_light_effect", timings: [ 800, 900, 850, 920, 780, 950, 820, 880 ] },
      { name: "call_hass_service", timings: [ 300, 350, 320, 380, 290, 400, 310, 360 ] }
    ]

    tools.each do |tool|
      tool[:timings].each do |timing|
        ToolMetrics.record(
          tool_name: tool[:name],
          duration_ms: timing + rand(-5..5), # Add some variance
          success: rand > 0.1 # 90% success rate
        )
      end
      puts "✅ Generated #{tool[:timings].length} metrics for #{tool[:name]}"
    end

    puts "\n🎉 Sample data generated! Run 'rake tools:summary' to see results."
  end
end
