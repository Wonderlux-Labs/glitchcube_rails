require 'rails_helper'

RSpec.describe SummaryTranscript do
  def log(session, at, user: "hi", ai: "yo")
    build(:conversation_log, session_id: session, user_message: user, ai_response: ai, created_at: at)
  end

  describe '.render' do
    let(:base) { Time.zone.parse("2026-07-06 02:00:00") }

    it 'joins turns with no marker within a single conversation' do
      out = described_class.render([
        log("s1", base, user: "one"),
        log("s1", base + 30, user: "two")
      ])

      expect(out).not_to include("new conversation")
      expect(out).to include("Visitor: one").and include("Visitor: two")
    end

    it 'marks a plain boundary when the session changes, with no wall-clock inference' do
      short = described_class.render([ log("s1", base), log("s2", base + 40) ])
      long  = described_class.render([ log("s1", base), log("s2", base + 20.minutes) ])

      expect(short).to include("═══ new conversation ═══")
      expect(long).to include("═══ new conversation ═══")
      # We no longer guess "same visitor" vs "new visitor" from the time gap.
      [ short, long ].each do |out|
        expect(out).not_to match(/re-triggering|NEW visitor|SAME visitor/)
      end
    end
  end
end
