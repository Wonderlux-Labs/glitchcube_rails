# frozen_string_literal: true

# Renders a chronological run of ConversationLogs into the flat transcript the
# summarizers read — but with a soft marker wherever the session (visitor) changes,
# so a summary can tell ONE long conversation from several separate ones.
#
# That distinction is what makes "once per conversation" style steering measurable:
# a gag repeated three times inside a single visitor's chat reads very differently
# from the same gag landing once each with three different people. The marker carries
# the time gap so the reader can infer intent — a few seconds usually means the same
# person re-triggering an interrupted chat; several minutes means a new visitor.
class SummaryTranscript
  # A short line the summarizer prompts can drop above the transcript so the model
  # reads the markers consistently.
  LEGEND = <<~LEGEND.strip
    (Separate visitor conversations are divided by "═══ new session" markers showing the
    time gap. A gap of seconds is usually the same person re-triggering after an interrupted
    turn; minutes or more is almost certainly a new visitor. Use this to tell a bit repeated
    within ONE conversation from the same bit landing once each with different people.)
  LEGEND

  def self.render(logs)
    new(logs).render
  end

  def initialize(logs)
    @logs = logs
  end

  def render
    parts = []
    previous = nil
    @logs.each do |log|
      parts << boundary(previous, log) if previous && log.session_id != previous.session_id
      parts << log.transcript_line
      previous = log
    end
    parts.join("\n\n")
  end

  private

  def boundary(previous, log)
    gap = (log.created_at - previous.created_at).to_i
    "═══ new session · #{log.created_at.strftime('%H:%M')} · #{gap_phrase(gap)} ═══"
  end

  def gap_phrase(seconds)
    "#{humanized(seconds)} after the previous turn — #{inference(seconds)}"
  end

  def humanized(seconds)
    return "#{seconds}s" if seconds < 60
    return "#{seconds / 60}m" if seconds < 3600

    "#{seconds / 3600}h"
  end

  def inference(seconds)
    return "likely the SAME visitor re-triggering an interrupted chat" if seconds < 120
    return "maybe the same visitor, maybe a new one" if seconds < 600

    "almost certainly a NEW visitor"
  end
end
