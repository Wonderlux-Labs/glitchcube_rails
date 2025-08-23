# app/jobs/summaries/summary_consolidation_job.rb

module Recurring
  module System
    module Summaries
      class SummaryConsolidationJob < ApplicationJob
  queue_as :default

  def perform
    return unless Rails.env.production? || Rails.env.development?

    Rails.logger.info "🗂️ SummaryConsolidationJob starting"

    # Only consolidate if we have a significant number of hourly summaries
    hourly_count = Summary.where(summary_type: "hourly").count

    if hourly_count < 12
      Rails.logger.info "📊 Only #{hourly_count} hourly summaries - skipping consolidation"
      return
    end

    Rails.logger.info "📊 Found #{hourly_count} hourly summaries - consolidating oldest batches"

    # Group oldest summaries into batches for consolidation
    consolidate_summaries_in_batches

    Rails.logger.info "✅ SummaryConsolidationJob completed successfully"
  rescue StandardError => e
    Rails.logger.error "❌ SummaryConsolidationJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  def consolidate_summaries_in_batches
    # Get the oldest 15 hourly summaries that aren't empty
    meaningful_summaries = Summary.where(summary_type: "hourly")
                                 .where.not(summary_text: [ "No conversations found in this time period.", "" ])
                                 .order(:created_at)
                                 .limit(15)

    if meaningful_summaries.count < 10
      Rails.logger.info "📊 Only #{meaningful_summaries.count} meaningful summaries - need at least 10 for consolidation"
      return
    end

    Rails.logger.info "🔄 Consolidating #{meaningful_summaries.count} meaningful summaries"

    # Create consolidated summary
    consolidated_summary = create_consolidated_summary(meaningful_summaries)

    if consolidated_summary.persisted?
      # Delete the original summaries
      original_ids = meaningful_summaries.pluck(:id)
      Summary.where(id: original_ids).destroy_all
      Rails.logger.info "🗑️ Deleted #{original_ids.count} original summaries after consolidation"
    end
  end

  def create_consolidated_summary(summaries)
    # Extract all metadata for analysis
    all_questions = []
    all_thoughts = []
    all_topics = []
    all_moods = []
    total_conversations = 0

    summaries.each do |summary|
      metadata = summary.metadata_json
      all_questions.concat(Array(metadata["important_questions"]))
      all_thoughts.concat(Array(metadata["useful_thoughts"]))
      all_topics.concat(Array(metadata["topics"]))
      all_moods << metadata["general_mood"] if metadata["general_mood"].present?
      total_conversations += metadata["conversations_count"].to_i
    end

    # Get time bounds
    start_time = summaries.minimum(:start_time)
    end_time = summaries.maximum(:end_time)
    total_messages = summaries.sum(:message_count)

    # Create consolidated text
    time_period = calculate_time_period(start_time, end_time)
    consolidated_text = generate_consolidated_summary_text(summaries, time_period)

    # Create the consolidated summary
    Summary.create!(
      summary_type: "consolidated",
      summary_text: consolidated_text,
      start_time: start_time,
      end_time: end_time,
      message_count: total_messages,
      metadata: {
        general_mood: dominant_mood(all_moods),
        important_questions: deduplicate_questions(all_questions),
        useful_thoughts: deduplicate_thoughts(all_thoughts),
        topics: all_topics.uniq,
        goal_progress: "multiple_periods",
        consolidated_from: summaries.count,
        total_conversations: total_conversations,
        time_period: time_period,
        conversation_ids: extract_all_conversation_ids(summaries)
      }.to_json
    )
  end

  def generate_consolidated_summary_text(summaries, time_period)
    themes = extract_common_themes(summaries)
    key_interactions = extract_key_interactions(summaries)

    <<~TEXT
      Consolidated summary covering #{time_period}:

      #{themes.any? ? "Key themes: #{themes.join(', ')}" : 'Mixed topics discussed'}

      #{key_interactions.any? ? "Notable interactions: #{key_interactions.join('; ')}" : 'Various conversations occurred'}

      This period showed #{calculate_activity_level(summaries)} activity with #{summaries.count} meaningful conversation periods.
    TEXT
  end

  def extract_common_themes(summaries)
    all_topics = summaries.flat_map do |summary|
      Array(summary.metadata_json["topics"])
    end

    # Count frequency and return top themes
    topic_counts = all_topics.tally
    topic_counts.select { |_, count| count > 1 }.keys.first(5)
  end

  def extract_key_interactions(summaries)
    summaries.filter_map do |summary|
      metadata = summary.metadata_json
      questions = Array(metadata["important_questions"])
      thoughts = Array(metadata["useful_thoughts"])

      if questions.any? || thoughts.any?
        "#{summary.summary_text.truncate(60)}"
      end
    end.first(3)
  end

  def calculate_activity_level(summaries)
    avg_exchanges = summaries.sum(&:message_count) / summaries.count.to_f
    case avg_exchanges
    when 0..2
      "low"
    when 2..8
      "moderate"
    else
      "high"
    end
  end

  def calculate_time_period(start_time, end_time)
    return "unknown period" unless start_time && end_time

    hours = ((end_time - start_time) / 1.hour).round(1)
    if hours < 24
      "#{hours} hours"
    else
      days = (hours / 24).round(1)
      "#{days} days"
    end
  end

  def dominant_mood(moods)
    return "neutral" if moods.empty?
    moods.tally.max_by { |_, count| count }&.first || "neutral"
  end

  def deduplicate_questions(questions)
    # Remove similar questions using basic similarity
    unique_questions = []
    questions.each do |q|
      next if q.blank?
      similar_exists = unique_questions.any? { |existing| similarity(q.downcase, existing.downcase) > 0.7 }
      unique_questions << q unless similar_exists
    end
    unique_questions.first(8)
  end

  def deduplicate_thoughts(thoughts)
    thoughts.uniq.first(10)
  end

  def similarity(a, b)
    # Simple Jaccard similarity for deduplication
    words_a = a.split
    words_b = b.split
    intersection = (words_a & words_b).length
    union = (words_a | words_b).length
    union.zero? ? 0 : intersection.to_f / union
  end

  def extract_all_conversation_ids(summaries)
    summaries.flat_map do |summary|
      Array(summary.metadata_json["conversation_ids"])
    end.uniq
  end
      end
    end
  end
end
