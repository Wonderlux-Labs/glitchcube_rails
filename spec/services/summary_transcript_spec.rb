require 'rails_helper'

RSpec.describe SummaryTranscript do
  def log(session, at, user: "hi", ai: "yo")
    build(:conversation_log, session_id: session, user_message: user, ai_response: ai, created_at: at)
  end

  describe '.render' do
    let(:base) { Time.zone.parse("2026-07-06 02:00:00") }

    it 'joins turns with no session marker within a single conversation' do
      out = described_class.render([
        log("s1", base, user: "one"),
        log("s1", base + 30, user: "two")
      ])

      expect(out).not_to include("new session")
      expect(out).to include("Visitor: one").and include("Visitor: two")
    end

    it 'marks a session change and infers a re-trigger on a short gap' do
      out = described_class.render([ log("s1", base), log("s2", base + 40) ])

      expect(out).to include("═══ new session")
      expect(out).to match(/SAME visitor re-triggering/)
    end

    it 'infers a new visitor when the gap between sessions is long' do
      out = described_class.render([ log("s1", base), log("s2", base + 20.minutes) ])

      expect(out).to include("═══ new session")
      expect(out).to match(/NEW visitor/)
    end
  end
end
