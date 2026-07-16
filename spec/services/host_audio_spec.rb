# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HostAudio do
  describe '.run' do
    it 'runs the command and returns once it exits' do
      expect { described_class.run("true", timeout: 5) }.not_to raise_error
    end

    it 'raises when the command fails' do
      expect { described_class.run("false", timeout: 5) }.to raise_error(/exit/)
    end

    it 'kills a hung process and raises after the timeout' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { described_class.run("sleep 30", timeout: 0.5) }.to raise_error(/timed out/)

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      expect(elapsed).to be < 5
    end
  end

  describe '.play' do
    before do
      allow(described_class).to receive(:run)
      # Default: quiet mode off (existing behavior).
      allow(HomeAssistantService).to receive(:entity_state).and_return(nil)
    end

    it 'plays the file via ffplay, capped at max_seconds with a fade-out' do
      described_class.play("/tmp/glitch cube.mp3", max_seconds: 90)

      expect(described_class).to have_received(:run) do |command, timeout:|
        expect(command).to include("ffplay")
        expect(command).to include("-nodisp")
        expect(command).to include("-autoexit")
        expect(command).to include("-t 90")
        expect(command).to include("afade=t=out:st=85:d=5")
        expect(command).to include(Shellwords.escape("/tmp/glitch cube.mp3"))
        expect(timeout).to be > 90
      end
    end

    it 'plays untruncated (no cap/fade) but still enforces a hard kill ceiling when max_seconds is omitted' do
      described_class.play("/tmp/song.mp3")

      expect(described_class).to have_received(:run) do |command, timeout:|
        expect(command).to include("ffplay")
        expect(command).to include("-autoexit")
        expect(command).not_to include("-t ")
        expect(command).not_to include("afade")
        expect(command).to include(Shellwords.escape("/tmp/song.mp3"))
        # A wedged ffplay must never be joined on forever: uncapped play still
        # gets the hard kill ceiling so it can't pin a SolidQueue worker.
        expect(timeout).to eq(described_class::UNCAPPED_KILL_CEILING)
      end
    end

    it 'omits the ffplay -volume flag when quiet mode is off' do
      described_class.play("/tmp/song.mp3", max_seconds: 30)

      expect(described_class).to have_received(:run) do |command, _|
        expect(command).not_to include("-volume")
      end
    end

    it 'caps ffplay volume at the quiet-mode setting when quiet mode is on' do
      allow(HomeAssistantService).to receive(:entity_state)
        .with("input_boolean.quiet_mode").and_return("on")
      allow(HomeAssistantService).to receive(:entity_state)
        .with("input_number.quiet_mode_max_volume").and_return("40.0")

      described_class.play("/tmp/song.mp3", max_seconds: 30)

      expect(described_class).to have_received(:run) do |command, _|
        expect(command).to include("-volume 40")
      end
    end

    it 'falls back to the default cap when quiet mode is on but no cap is set' do
      allow(HomeAssistantService).to receive(:entity_state)
        .with("input_boolean.quiet_mode").and_return("on")
      allow(HomeAssistantService).to receive(:entity_state)
        .with("input_number.quiet_mode_max_volume").and_return(nil)

      described_class.play("/tmp/song.mp3", max_seconds: 30)

      expect(described_class).to have_received(:run) do |command, _|
        expect(command).to include("-volume #{HostAudio::DEFAULT_QUIET_VOLUME}")
      end
    end

    it 'honors an explicit volume when quiet mode is off' do
      described_class.play("/tmp/song.mp3", max_seconds: 30, volume: 70)

      expect(described_class).to have_received(:run) do |command, _|
        expect(command).to include("-volume 70")
      end
    end

    it 'clamps an explicit volume down to the quiet-mode cap (min of the two)' do
      allow(HomeAssistantService).to receive(:entity_state)
        .with("input_boolean.quiet_mode").and_return("on")
      allow(HomeAssistantService).to receive(:entity_state)
        .with("input_number.quiet_mode_max_volume").and_return("40")

      described_class.play("/tmp/song.mp3", max_seconds: 30, volume: 90)

      expect(described_class).to have_received(:run) do |command, _|
        expect(command).to include("-volume 40")
      end
    end

    it 'keeps an explicit volume below the cap unchanged' do
      allow(HomeAssistantService).to receive(:entity_state)
        .with("input_boolean.quiet_mode").and_return("on")
      allow(HomeAssistantService).to receive(:entity_state)
        .with("input_number.quiet_mode_max_volume").and_return("80")

      described_class.play("/tmp/song.mp3", max_seconds: 30, volume: 25)

      expect(described_class).to have_received(:run) do |command, _|
        expect(command).to include("-volume 25")
      end
    end
  end

  describe '.play_random_theme_song' do
    let(:songs_dir) { Pathname.new(Dir.mktmpdir) }

    before do
      allow(described_class).to receive(:play)
      stub_const("HostAudio::THEME_SONGS_DIR", songs_dir)
    end

    after { FileUtils.remove_entry(songs_dir) }

    it 'plays a random .mp3 from the theme dir and returns it' do
      FileUtils.touch(songs_dir.join("theme_a.mp3"))
      FileUtils.touch(songs_dir.join("theme_b.mp3"))

      result = described_class.play_random_theme_song(max_seconds: 42)

      expect(result.to_s).to match(%r{#{songs_dir}/theme_[ab]\.mp3})
      expect(described_class).to have_received(:play)
        .with(result, max_seconds: 42, volume: nil)
    end

    it 'no-ops and returns nil when the theme dir is empty' do
      expect(described_class.play_random_theme_song).to be_nil
      expect(described_class).not_to have_received(:play)
    end
  end

  describe '.say' do
    before do
      allow(described_class).to receive(:run)
      allow(HomeAssistantService).to receive(:entity_state).and_return(nil)
    end

    it 'speaks through the host say command with a robotic voice' do
      described_class.say("CUBE ANOMALY. PERSONA UNSTABLE.")

      expect(described_class).to have_received(:run) do |command, timeout:|
        expect(command).to start_with("say -v ")
        expect(command).to include(Shellwords.escape("CUBE ANOMALY. PERSONA UNSTABLE."))
        expect(command).not_to include("volm")
        expect(timeout).to be > 0
      end
    end

    it 'prepends an inline volume command when quiet mode is on' do
      allow(HomeAssistantService).to receive(:entity_state)
        .with("input_boolean.quiet_mode").and_return("on")
      allow(HomeAssistantService).to receive(:entity_state)
        .with("input_number.quiet_mode_max_volume").and_return("30")

      described_class.say("QUIET DOWN")

      expect(described_class).to have_received(:run) do |command, _|
        expect(command).to include(Shellwords.escape("[[volm 0.3]]QUIET DOWN"))
      end
    end

    it 'prepends an inline volume command for an explicit volume with quiet mode off' do
      described_class.say("HELLO", volume: 50)

      expect(described_class).to have_received(:run) do |command, _|
        expect(command).to include(Shellwords.escape("[[volm 0.5]]HELLO"))
      end
    end

    it 'clamps an explicit say volume down to the quiet-mode cap' do
      allow(HomeAssistantService).to receive(:entity_state)
        .with("input_boolean.quiet_mode").and_return("on")
      allow(HomeAssistantService).to receive(:entity_state)
        .with("input_number.quiet_mode_max_volume").and_return("20")

      described_class.say("HELLO", volume: 90)

      expect(described_class).to have_received(:run) do |command, _|
        expect(command).to include(Shellwords.escape("[[volm 0.2]]HELLO"))
      end
    end
  end
end
