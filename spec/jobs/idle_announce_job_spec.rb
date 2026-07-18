# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IdleAnnounceJob, type: :job do
  include ActiveJob::TestHelper

  let(:fake_ha) { FakeHomeAssistant.new(persona: 'jax') }

  let(:narrative) do
    {
      'speech' => 'Nobody around, huh? Fine. I will just talk to this rock over here.',
      'continue_conversation' => false,
      'inner_monologue' => 'so bored',
      'marquee' => 'HELLO???'
    }
  end

  let(:brain_response) do
    double(
      'BrainResponse',
      content: narrative.to_json,
      structured_output: narrative,
      model: 'test/brain',
      usage: { 'total_tokens' => 10 }
    )
  end

  before do
    HomeAssistantService.instance = fake_ha
    allow(LlmService).to receive(:call_with_structured_output).and_return(brain_response)
    allow(EnvironmentDirectorJob).to receive(:perform_later)
  end

  after { HomeAssistantService.reset_instance! }

  it 'announces the musing without opening the mic' do
    described_class.new.perform

    calls = fake_ha.service_calls_for('assist_satellite')
    expect(calls.length).to eq(1)
    expect(calls.first[:service]).to eq('announce')
    expect(calls.first[:data][:entity_id]).to eq(Shows::Base::SATELLITE)
    expect(calls.first[:data][:message]).to eq(narrative['speech'])
  end

  it 'never opens a conversation (no start_conversation call, no Conversation/ConversationLog rows)' do
    expect {
      described_class.new.perform
    }.not_to change { Conversation.count }

    expect(ConversationLog.count).to eq(0)
    expect(fake_ha.service_calls_for('assist_satellite').map { |c| c[:service] }).not_to include('start_conversation')
  end

  it 'dispatches non-narrative action channels through the two-lane translator with conversation_id: nil' do
    described_class.new.perform

    expect(EnvironmentDirectorJob).to have_received(:perform_later).with(
      hash_including(instruction: 'marquee: HELLO???', conversation_id: nil, convo_prefix: 'cube_env')
    )
  end

  it 'skips the announce entirely when the brain call fails (fallback narrative)' do
    allow(LlmService).to receive(:call_with_structured_output).and_raise('OpenRouter API timeout')

    described_class.new.perform

    expect(fake_ha.service_calls_for('assist_satellite')).to be_empty
  end

  it 'runs from the enqueued job pipeline' do
    perform_enqueued_jobs do
      described_class.perform_later
    end

    expect(fake_ha.service_calls_for('assist_satellite')).not_to be_empty
  end
end
