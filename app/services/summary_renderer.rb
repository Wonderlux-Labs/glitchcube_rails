# frozen_string_literal: true

# Shared, structured rendering of Summary rows for prompt material and context injection.
# One place for the labeled-line format and Eastern-time range formatting, so the persona
# fold, the overall digest, and the context builder all read summaries the same way instead
# of hand-rolling inline strings. Times render in Eastern (config.time_zone) with an "ET" tag.
module SummaryRenderer
  module_function

  # A factual interaction chunk → labeled lines with an ET time range.
  def interaction_chunk(summary)
    meta = summary.metadata_json
    lines = [ "Chunk (#{time_range(summary)}):", summary.summary_text.to_s.strip ]
    lines << "Visitor-reported facts: #{meta['real_world_facts']}" if meta["real_world_facts"].present?
    lines << "Threads left open: #{meta['active_threads']}" if meta["active_threads"].present?
    lines.join("\n")
  end

  # A neutral handoff report → persona-labeled with an ET time range.
  def handoff(summary)
    "#{persona_label(summary)} — #{time_range(summary)}: #{summary.summary_text.to_s.strip}"
  end

  def persona_label(summary)
    summary.persona&.name || summary.persona&.slug || "A persona"
  end

  # "8:12–8:31 PM ET", collapsing to a single time when the span is a point or unknown.
  def time_range(summary)
    start_at = summary.start_time
    finish_at = summary.end_time
    return clock(finish_at || start_at) if start_at.blank? || finish_at.blank? || start_at.to_i == finish_at.to_i

    same_meridiem = start_at.in_time_zone.strftime("%p") == finish_at.in_time_zone.strftime("%p")
    from = same_meridiem ? start_at.in_time_zone.strftime("%-l:%M") : clock(start_at)
    "#{from}–#{clock(finish_at)}"
  end

  def clock(time)
    return "unknown time" if time.blank?

    "#{time.in_time_zone.strftime('%-l:%M %p')} ET"
  end
end
