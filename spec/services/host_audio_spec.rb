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
    before { allow(described_class).to receive(:run) }

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
  end

  describe '.say' do
    before { allow(described_class).to receive(:run) }

    it 'speaks through the host say command with a robotic voice' do
      described_class.say("CUBE ANOMALY. PERSONA UNSTABLE.")

      expect(described_class).to have_received(:run) do |command, timeout:|
        expect(command).to start_with("say -v ")
        expect(command).to include(Shellwords.escape("CUBE ANOMALY. PERSONA UNSTABLE."))
        expect(timeout).to be > 0
      end
    end
  end
end
