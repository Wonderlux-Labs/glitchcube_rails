# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SummarizerService do
  let(:conversation) { create(:conversation) }

  def stub_llm(summary:, ooc_note: nil, real_world_facts: nil)
    payload = { "summary" => summary }
    payload["ooc_note"] = ooc_note unless ooc_note.nil?
    payload["real_world_facts"] = real_world_facts unless real_world_facts.nil?
    allow(LlmService).to receive(:call_with_structured_output)
      .and_return(double(structured_output: payload))
  end

  context 'with new interactions' do
    before do
      create(:conversation_log, conversation: conversation, user_message: "hi",
             ai_response: "hey there", created_at: 5.minutes.ago)
      create(:conversation_log, conversation: conversation, user_message: "what's up",
             ai_response: "vibing", created_at: 4.minutes.ago)
    end

    it 'writes a recent Summary from the interactions' do
      stub_llm(summary: "Two folks stopped by and chatted.")

      result = described_class.call

      expect(result.success?).to be(true)
      summary = Summary.by_type('interaction').last
      expect(summary.summary_text).to eq("Two folks stopped by and chatted.")
      expect(summary.message_count).to eq(2)
      expect(summary.start_time).to be_present
      expect(summary.end_time).to be_present
    end

    it 'stores an ooc_note in metadata only when the model provides one' do
      stub_llm(summary: "rowdy crowd", ooc_note: "cube_light seems stuck on red — avoid it")
      described_class.call
      expect(Summary.by_type('interaction').last.metadata_json['ooc_note'])
        .to eq("cube_light seems stuck on red — avoid it")
    end

    it 'omits ooc_note from metadata when the model leaves it blank' do
      stub_llm(summary: "quiet stretch", ooc_note: "")
      described_class.call
      expect(Summary.by_type('interaction').last.metadata_json).not_to have_key('ooc_note')
    end

    it 'stores real_world_facts in metadata when provided' do
      stub_llm(summary: "chatty crowd", real_world_facts: "Mars said it's her 4th visit. Dance party at the Corral at 2am.")
      described_class.call
      expect(Summary.by_type('interaction').last.metadata_json['real_world_facts'])
        .to eq("Mars said it's her 4th visit. Dance party at the Corral at 2am.")
    end

    it 'feeds the most recent prior summary as context and uses the summarizer model' do
      create(:summary, summary_type: 'interaction', summary_text: 'earlier: someone named Mars',
             end_time: 10.minutes.ago)

      expect(LlmService).to receive(:call_with_structured_output) do |args|
        expect(args[:model]).to eq(SummarizerService::MODEL)
        expect(args[:messages].last[:content]).to include('earlier: someone named Mars')
        double(structured_output: { "summary" => "Mars came back." })
      end

      described_class.call
      expect(Summary.by_type('interaction').last.summary_text).to eq("Mars came back.")
    end
  end

  context 'with no new interactions since the last summary' do
    it 'skips without creating a summary' do
      create(:summary, summary_type: 'interaction', end_time: 1.minute.ago)

      result = described_class.call

      expect(result.success?).to be(true)
      expect(result.data[:skipped]).to be(true)
      expect(Summary.by_type('interaction').count).to eq(1) # only the pre-existing one
    end
  end

  it 'skips when the model returns a blank summary' do
    create(:conversation_log, conversation: conversation, user_message: "hi",
           ai_response: "hey", created_at: 2.minutes.ago)
    stub_llm(summary: "   ")

    result = described_class.call

    expect(result.data[:skipped]).to be(true)
    expect(Summary.by_type('interaction')).to be_empty
  end
end
