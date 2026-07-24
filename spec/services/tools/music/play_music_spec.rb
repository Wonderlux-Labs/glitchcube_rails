# frozen_string_literal: true

require "rails_helper"

# Wraps script.play_music_on_jukebox. query + volume are both REQUIRED (volume decides
# background vs front-and-center); queue is optional (defaults replace, script-side).
RSpec.describe Tools::Music::PlayMusic, :allow_ha_calls do
  let(:fake_ha) { FakeHomeAssistant.new }

  before { HomeAssistantService.instance = fake_ha }
  after { HomeAssistantService.reset_instance! }

  def last_call
    fake_ha.service_calls_for("script").last
  end

  it "fires play_music_on_jukebox with query and volume" do
    Tools::Music::PlayMusic.call(query: "Nirvana - Smells Like Teen Spirit", volume: 85)

    expect(last_call[:data][:entity_id]).to eq("script.play_music_on_jukebox")
    expect(last_call[:data][:variables]).to include(query: "Nirvana - Smells Like Teen Spirit", volume: 85)
  end

  it "forwards queue when provided and omits it otherwise" do
    Tools::Music::PlayMusic.call(query: "jazz", volume: 30, queue: "replace_next")
    expect(last_call[:data][:variables][:queue]).to eq("replace_next")

    Tools::Music::PlayMusic.call(query: "jazz", volume: 30)
    expect(last_call[:data][:variables].keys).to contain_exactly(:query, :volume)
  end

  it "requires a query" do
    result = Tools::Music::PlayMusic.call(query: "", volume: 50)

    expect(result[:success]).to be(false)
    expect(fake_ha.service_calls).to be_empty
  end

  it "validates volume is present and 0-100 at the definition layer" do
    definition = Tools::Music::PlayMusic.definition
    errors = []
    definition.validation_blocks.each { |b| b.call({ "query" => "x", "volume" => 150 }, errors) }

    expect(errors.join).to match(/volume/i)
  end

  it "is named play_music" do
    expect(Tools::Music::PlayMusic.definition.name).to eq("play_music")
  end
end
