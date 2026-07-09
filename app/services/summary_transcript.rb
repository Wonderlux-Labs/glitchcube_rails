# frozen_string_literal: true

# Renders a chronological run of ConversationLogs into the flat transcript the
# summarizers read, with a plain marker wherever HASS started a new conversation
# (session), so a summary can tell ONE long conversation from several separate ones.
#
# We deliberately do NOT try to infer "same visitor vs new visitor" from the time gap:
# that was wall-clock-dependent and wrong under fast/scripted runs, and the model can
# tell far better from what people actually SAY ("Hi, I'm Marco" vs picking up a thread).
# The marker is just the structural signal — a fresh conversation began here.
class SummaryTranscript
  # A short line the summarizer prompts can drop above the transcript so the model
  # reads the markers consistently.
  LEGEND = <<~LEGEND.strip
    (Separate visitor conversations are divided by "═══ new conversation ═══" markers. Read what
    people say to tell whether it's the same person picking a thread back up or a brand-new
    visitor — that's usually obvious from the dialogue.)
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
      parts << "═══ new conversation ═══" if previous && log.session_id != previous.session_id
      parts << log.transcript_line
      previous = log
    end
    parts.join("\n\n")
  end
end
