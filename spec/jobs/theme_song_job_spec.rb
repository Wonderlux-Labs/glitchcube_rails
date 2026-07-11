# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ThemeSongJob, type: :job do
  it 'plays a random theme song, passing the cap through' do
    allow(HostAudio).to receive(:play_random_theme_song)

    described_class.perform_now(30)

    expect(HostAudio).to have_received(:play_random_theme_song).with(max_seconds: 30)
  end

  it 'defaults to an uncapped play' do
    allow(HostAudio).to receive(:play_random_theme_song)

    described_class.perform_now

    expect(HostAudio).to have_received(:play_random_theme_song).with(max_seconds: nil)
  end
end
