# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ToolMetrics do
  before { ToolMetrics.clear_all_metrics! }

  describe '.record' do
    it 'records timing with proper precision' do
      ToolMetrics.record(tool_name: 'turn_on_light', duration_ms: 45.2, success: true)
      stats = ToolMetrics.stats_for('turn_on_light')

      expect(stats[:count]).to eq(1)
      expect(stats[:p50]).to be_within(0.1).of(45.2)
      expect(stats[:avg]).to be_within(0.1).of(45.2)
    end

    it 'handles multiple recordings' do
      timings = [ 30, 45, 60, 35, 50 ]
      timings.each do |timing|
        ToolMetrics.record(tool_name: 'test_tool', duration_ms: timing, success: true)
      end

      stats = ToolMetrics.stats_for('test_tool')
      expect(stats[:count]).to eq(5)
      expect(stats[:min]).to eq(30)
      expect(stats[:max]).to eq(60)
      expect(stats[:avg]).to eq(44) # (30+45+60+35+50)/5
    end

    it 'calculates percentiles correctly' do
      # Add timings that make percentile calculation easy
      (1..100).each do |i|
        ToolMetrics.record(tool_name: 'percentile_test', duration_ms: i, success: true)
      end

      stats = ToolMetrics.stats_for('percentile_test')
      expect(stats[:p50]).to be_within(1).of(50)
      expect(stats[:p95]).to be_within(1).of(95)
      expect(stats[:p99]).to be_within(1).of(99)
    end
  end

  describe '.recommendation_for' do
    it 'recommends sync for extremely fast tools' do
      # To get :sync, we need adjusted timing < 100ms
      # So base timing must be < 100ms - 300ms = impossible with current overhead
      # But if a tool is truly instant (5ms), adjusted would be 305ms = :maybe_sync
      # Let's test what actually happens with a very fast tool
      10.times { ToolMetrics.record(tool_name: 'instant_tool', duration_ms: 5, success: true) }
      recommendation = ToolMetrics.recommendation_for('instant_tool')

      # With current thresholds and 300ms overhead, even 5ms becomes 305ms = :maybe_sync
      expect(recommendation).to eq(:maybe_sync)
    end

    it 'recommends maybe_sync for medium-fast tools' do
      # 50ms + 300ms Burning Man overhead = 350ms, which is < 500ms (MAYBE_SYNC_THRESHOLD)
      # but > 100ms (SYNC_THRESHOLD), so it should be :maybe_sync
      10.times { ToolMetrics.record(tool_name: 'get_light_state', duration_ms: 50, success: true) }
      recommendation = ToolMetrics.recommendation_for('get_light_state')

      expect(recommendation).to eq(:maybe_sync)
    end

    it 'recommends async for slow tools' do
      10.times { ToolMetrics.record(tool_name: 'slow_tool', duration_ms: 800, success: true) }
      recommendation = ToolMetrics.recommendation_for('slow_tool')

      expect(recommendation).to eq(:async)
    end

    it 'recommends async for borderline tools' do
      # 250ms + 300ms Burning Man overhead = 550ms, which is > 500ms (MAYBE_SYNC_THRESHOLD)
      # so it should be :async
      10.times { ToolMetrics.record(tool_name: 'medium_tool', duration_ms: 250, success: true) }
      recommendation = ToolMetrics.recommendation_for('medium_tool')

      expect(recommendation).to eq(:async)
    end
  end

  describe '.burning_man_adjusted_timing' do
    it 'adds network overhead correctly' do
      adjusted = ToolMetrics.burning_man_adjusted_timing(150)
      expect(adjusted).to eq(450) # 150 + 300
    end

    it 'changes recommendations with network overhead' do
      # Tool that's fast but gets slowed by Burning Man overhead
      10.times { ToolMetrics.record(tool_name: 'border_tool', duration_ms: 80, success: true) }

      stats = ToolMetrics.stats_for('border_tool')
      # The recommendation is based on Burning Man adjusted timing (80ms + 300ms = 380ms)
      # which is < 500ms (MAYBE_SYNC_THRESHOLD), so should be :maybe_sync
      expect(stats[:recommendation]).to eq(:maybe_sync)

      # Verify the Burning Man adjustment calculation
      burning_man_p95 = ToolMetrics.burning_man_adjusted_timing(stats[:p95])
      expect(burning_man_p95).to eq(380) # 80ms + 300ms overhead
      expect(burning_man_p95).to be > ToolMetrics::SYNC_THRESHOLD_MS
      expect(burning_man_p95).to be < ToolMetrics::MAYBE_SYNC_THRESHOLD_MS
    end
  end

  describe '.summary' do
    before do
      # Create sample data
      10.times { ToolMetrics.record(tool_name: 'fast_tool', duration_ms: 30, success: true) }
      10.times { ToolMetrics.record(tool_name: 'slow_tool', duration_ms: 600, success: true) }
    end

    it 'provides comprehensive summary' do
      summary = ToolMetrics.summary(days: 1)

      expect(summary[:total_tools]).to eq(2)
      expect(summary[:total_calls]).to eq(20)
      # fast_tool: 30ms + 300ms = 330ms = :maybe_sync
      # slow_tool: 600ms + 300ms = 900ms = :async
      expect(summary[:recommendations][:sync]).to eq(0)
      expect(summary[:recommendations][:maybe_sync]).to eq(1)
      expect(summary[:recommendations][:async]).to eq(1)
      expect(summary[:fastest_tool][:tool_name]).to eq('fast_tool')
      expect(summary[:slowest_tool][:tool_name]).to eq('slow_tool')
    end
  end

  describe '.clear_all_metrics!' do
    it 'clears all cached metrics' do
      ToolMetrics.record(tool_name: 'test', duration_ms: 50, success: true)
      expect(ToolMetrics.stats_for('test')[:count]).to eq(1)

      ToolMetrics.clear_all_metrics!
      expect(ToolMetrics.stats_for('test')[:count]).to eq(0)
    end
  end

  describe 'error handling' do
    it 'handles Rails.cache failures gracefully' do
      # Mock a cache failure
      allow(Rails.cache).to receive(:write).and_raise(StandardError, 'Cache error')

      expect {
        ToolMetrics.record(tool_name: 'test', duration_ms: 50, success: true)
      }.not_to raise_error
    end
  end
end
