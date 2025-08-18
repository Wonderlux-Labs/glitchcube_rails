# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationMemoryJob, type: :job do
  let!(:conversation) { create(:conversation, session_id: 'test-session', persona: 'buddy') }
  let!(:log1) {
    ConversationLog.create!(
      conversation: conversation,
      session_id: conversation.session_id,
      user_message: 'Hey, there\'s a fire performance at Center Camp tomorrow at 8pm',
      ai_response: 'That sounds amazing! Fire performances are always spectacular.'
    )
  }
  let!(:log2) {
    ConversationLog.create!(
      conversation: conversation,
      session_id: conversation.session_id,
      user_message: 'Yeah, and after that we should check out the art at the Temple',
      ai_response: 'Absolutely! The Temple is always so moving and beautiful.'
    )
  }
  let!(:log3) {
    ConversationLog.create!(
      conversation: conversation,
      session_id: conversation.session_id,
      user_message: 'Perfect, see you at 6:00 and Esplanade before the show',
      ai_response: 'Sounds like a plan! Looking forward to it.'
    )
  }

  subject { described_class.new }

  describe '#extract_locations' do
    it 'extracts Burning Man locations from conversation text' do
      text = "Let's meet at Center Camp, then head to the Temple and maybe check out the Trash Fence"
      context = { location: 'Black Rock City' }

      locations = subject.send(:extract_locations, text, context)

      expect(locations).to include('Center Camp', 'Temple', 'Trash Fence')
    end

    it 'extracts street addresses' do
      text = "I'll be at 6:00 and Esplanade, then moving to 3:30 and A"
      context = { location: 'Black Rock City' }

      locations = subject.send(:extract_locations, text, context)

      expect(locations).to include('6:00 and Esplanade')
    end

    it 'extracts camp names' do
      text = "Great show at Fractal Camp and nice party near Robot Heart"
      context = { location: 'Black Rock City' }

      locations = subject.send(:extract_locations, text, context)

      expect(locations.any? { |loc| loc.include?('Fractal Camp') }).to be true
    end
  end

  describe '#extract_events' do
    it 'extracts events with specific times' do
      text = "There's a fire performance at Center Camp tomorrow at 8pm"
      session_id = 'test-session'
      context = { location: 'Black Rock City' }

      events = subject.send(:extract_events, text, session_id, context)

      expect(events).not_to be_empty
      event = events.first
      expect(event[:title]).to include('fire performance')
      expect(event[:event_time]).to be > Time.current
      expect(event[:location]).to eq('Center Camp') # It extracts the specific location mentioned
    end

    it 'handles "happening at" pattern' do
      text = "Art installation happening at 7pm today"
      session_id = 'test-session'
      context = { location: 'Black Rock City' }

      events = subject.send(:extract_events, text, session_id, context)

      expect(events).not_to be_empty
      expect(events.first[:title]).to include('Art installation')
    end
  end

  describe '#parse_event_time' do
    it 'parses PM times correctly' do
      context = { location: 'Black Rock City' }

      time = subject.send(:parse_event_time, '8pm', context)

      expect(time.hour).to eq(20)
    end

    it 'parses AM times correctly' do
      context = { location: 'Black Rock City' }

      time = subject.send(:parse_event_time, '9am', context)

      expect(time.hour).to eq(9)
    end

    it 'adds day if time has passed today' do
      context = { location: 'Black Rock City' }
      past_time = (Time.current - 2.hours).strftime('%l%p').strip.downcase

      time = subject.send(:parse_event_time, past_time, context)

      expect(time).to be > Time.current
    end
  end

  describe '#perform' do
    before do
      conversation.update!(ended_at: Time.current)
    end

    it 'creates conversation memories with location data' do
      expect {
        subject.perform(conversation.session_id)
      }.to change(ConversationMemory, :count).by(1)

      memory = ConversationMemory.last
      metadata = memory.metadata_json

      expect(metadata['locations']).to include('Center Camp', 'Temple')
      expect(metadata['events_mentioned']).to be > 0
    end

    it 'creates Event records for extracted events' do
      expect {
        subject.perform(conversation.session_id)
      }.to change(Event, :count).by_at_least(1)

      event = Event.last
      expect(event.title).to include('fire performance')
      expect(event.extracted_from_session).to eq(conversation.session_id)
      expect(event.upcoming?).to be true
    end

    it 'does not create duplicate events' do
      # Run twice
      subject.perform(conversation.session_id)
      initial_count = Event.count

      subject.perform(conversation.session_id)

      expect(Event.count).to eq(initial_count)
    end

    it 'skips creation for conversations with fewer than 3 logs' do
      short_conversation = create(:conversation, session_id: 'short-session', ended_at: Time.current)
      ConversationLog.create!(
        conversation: short_conversation,
        session_id: short_conversation.session_id,
        user_message: 'Hi',
        ai_response: 'Hello'
      )

      expect {
        subject.perform(short_conversation.session_id)
      }.not_to change(ConversationMemory, :count)
    end
  end
end
