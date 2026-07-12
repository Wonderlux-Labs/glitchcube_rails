# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recurring::Persona::RandomPersonaJob do
  before { Rails.cache.delete(described_class::NEXT_SWITCH_KEY) }

  it 'does not switch on the first run — it establishes the interval' do
    expect(CubePersona).not_to receive(:set_random)

    described_class.new.perform

    expect(Rails.cache.read(described_class::NEXT_SWITCH_KEY)).to be_present
  end

  it 'does not switch before the interval has elapsed' do
    Rails.cache.write(described_class::NEXT_SWITCH_KEY, 20.minutes.from_now.iso8601, expires_in: 6.hours)
    expect(CubePersona).not_to receive(:set_random)

    described_class.new.perform
  end

  it 'switches and rolls a fresh interval once the interval has elapsed' do
    Rails.cache.write(described_class::NEXT_SWITCH_KEY, 1.minute.ago.iso8601, expires_in: 6.hours)
    expect(CubePersona).to receive(:set_random)

    described_class.new.perform

    next_at = Time.parse(Rails.cache.read(described_class::NEXT_SWITCH_KEY))
    expect(next_at).to be_between(described_class::MIN_MINUTES.minutes.from_now - 1.minute,
                                  described_class::MAX_MINUTES.minutes.from_now + 1.minute)
  end
end
