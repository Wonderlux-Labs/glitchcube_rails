# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SummarizerService do
  let!(:neon) { Persona.create!(slug: "neon", name: "Neon") }

  def stub_llm(summary:, real_world_facts: nil, active_threads: nil)
    payload = { "summary" => summary }
    payload["real_world_facts"] = real_world_facts unless real_world_facts.nil?
    payload["active_threads"] = active_threads unless active_threads.nil?
    allow(LlmService).to receive(:call_with_structured_output)
      .and_return(double(structured_output: payload))
  end

  def convo_with_logs(persona_slug:, prefix:, count: 2, at: 5.minutes.ago)
    convo = create(:conversation, persona: persona_slug)
    count.times do |i|
      create(:conversation_log, conversation: convo,
             user_message: "#{prefix}-u#{i}", ai_response: "#{prefix}-a#{i}", created_at: at + i.seconds)
    end
    convo
  end

  context 'with new interactions for the persona' do
    before do
      convo_with_logs(persona_slug: "neon", prefix: "NEON", at: 5.minutes.ago)
      convo_with_logs(persona_slug: "buddy", prefix: "BUDDY", at: 4.minutes.ago) # different persona — excluded
    end

    it 'writes a persona-scoped interaction chunk from ONLY that persona’s conversations' do
      stub_llm(summary: "Two folks stopped by and chatted.")

      result = described_class.call("neon")

      expect(result.success?).to be(true)
      summary = Summary.interaction.last
      expect(summary.summary_text).to eq("Two folks stopped by and chatted.")
      expect(summary.persona).to eq(neon)
      expect(summary.message_count).to eq(2) # neon's 2 logs only, not buddy's
      expect(summary.start_time).to be_present
      expect(summary.end_time).to be_present
    end

    it 'feeds only this persona’s logs into the material' do
      expect(LlmService).to receive(:call_with_structured_output) do |args|
        material = args[:messages].last[:content]
        expect(material).to include("NEON-u0")
        expect(material).not_to include("BUDDY")
        double(structured_output: { "summary" => "ok" })
      end
      described_class.call("neon")
    end

    it 'stores real_world_facts in metadata when provided' do
      stub_llm(summary: "chatty crowd", real_world_facts: "Mars said it's her 4th visit. Dance party at the Corral at 2am.")
      described_class.call("neon")
      expect(Summary.interaction.last.metadata_json['real_world_facts'])
        .to eq("Mars said it's her 4th visit. Dance party at the Corral at 2am.")
    end

    it 'stores active_threads in metadata when provided' do
      stub_llm(summary: "chatty crowd", active_threads: "Laurie said she'd be back at midnight for a reading.")
      described_class.call("neon")
      expect(Summary.interaction.last.metadata_json['active_threads'])
        .to eq("Laurie said she'd be back at midnight for a reading.")
    end

    it 'never emits a steering ooc_note (steering moved to persona/overall)' do
      stub_llm(summary: "rowdy crowd")
      described_class.call("neon")
      expect(Summary.interaction.last.metadata_json).not_to have_key('ooc_note')
    end

    it 'reads only this persona’s logs since its own last chunk' do
      create(:summary, summary_type: 'interaction', persona: neon,
             summary_text: 'earlier: someone named Mars', end_time: 10.minutes.ago)

      expect(LlmService).to receive(:call_with_structured_output) do |args|
        expect(args[:model]).to eq(SummarizerService::MODEL)
        expect(args[:messages].last[:content]).to include('earlier: someone named Mars')
        double(structured_output: { "summary" => "Mars came back." })
      end

      described_class.call("neon")
      expect(Summary.interaction.where(persona: neon).last.summary_text).to eq("Mars came back.")
    end
  end

  context 'with no new interactions since the persona’s last chunk' do
    it 'skips without creating a chunk' do
      create(:summary, summary_type: 'interaction', persona: neon, end_time: 1.minute.ago)

      result = described_class.call("neon")

      expect(result.success?).to be(true)
      expect(result.data[:skipped]).to be(true)
      expect(Summary.interaction.count).to eq(1) # only the pre-existing one
    end
  end

  it 'skips when the model returns a blank summary' do
    convo_with_logs(persona_slug: "neon", prefix: "NEON", at: 2.minutes.ago)
    stub_llm(summary: "   ")

    result = described_class.call("neon")

    expect(result.data[:skipped]).to be(true)
    expect(Summary.interaction).to be_empty
  end

  it 'fails for an unknown persona' do
    expect(described_class.call("nobody").success?).to be(false)
  end
end
