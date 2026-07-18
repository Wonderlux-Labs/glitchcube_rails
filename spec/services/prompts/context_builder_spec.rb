# spec/services/prompts/context_builder_spec.rb
require 'rails_helper'

RSpec.describe Prompts::ContextBuilder do
  before { allow(HomeAssistantService).to receive(:entity).and_return(nil) }

  describe '.build' do
    it 'delegates to the instance' do
      expect_any_instance_of(described_class).to receive(:build).and_return("ctx")
      expect(described_class.build(persona: "buddy")).to eq("ctx")
    end
  end

  describe '#build' do
    subject { described_class.new(persona: persona_slug).build }
    let(:persona_slug) { nil }

    context 'world state' do
      it 'injects the world-state sensor content verbatim' do
        allow(HomeAssistantService).to receive(:entity).with("sensor.glitchcube_world_state")
          .and_return({ "attributes" => { "content" => "It is 12:55 AM and it is dark out." } })
        expect(subject).to include("Right now: It is 12:55 AM and it is dark out.")
      end

      it 'places live world state LAST, after the bigger picture' do
        create(:summary, summary_type: 'overall', summary_text: 'A rowdy night.', created_at: 1.minute.ago)
        allow(HomeAssistantService).to receive(:entity).with("sensor.glitchcube_world_state")
          .and_return({ "attributes" => { "content" => "It is dark out." } })
        expect(subject.index("The bigger picture")).to be < subject.index("Right now:")
      end

      it 'fails open when the fetch raises' do
        allow(HomeAssistantService).to receive(:entity).with("sensor.glitchcube_world_state")
          .and_raise(StandardError, "HASS down")
        expect(Rails.logger).to receive(:warn).with(/Could not load sensor.glitchcube_world_state/)
        expect { subject }.not_to raise_error
      end
    end

    context 'camera view' do
      def stub_camera(state)
        allow(HomeAssistantService).to receive(:entity).with("input_text.current_camera_state")
          .and_return({ "state" => state })
      end

      it 'injects the camera description when the input_text is present' do
        stub_camera("Two people in glittery jackets, laughing.")
        expect(subject).to include("Right now, your camera shows: Two people in glittery jackets, laughing.")
      end

      it 'omits the camera view when the camera is disabled in config, even with a description present' do
        allow(Rails.configuration).to receive(:disable_camera).and_return(true)
        stub_camera("Two people in glittery jackets, laughing.")
        expect(subject).not_to include("your camera shows")
      end

      it 'injects nothing when the input_text is an empty string' do
        stub_camera("")
        expect(subject).not_to include("your camera shows")
      end

      it 'injects nothing when the entity is missing (nil)' do
        # default before-block already returns nil for every entity
        expect(subject).not_to include("your camera shows")
      end

      it 'places the camera view LAST, after the live world state' do
        allow(HomeAssistantService).to receive(:entity).with("sensor.glitchcube_world_state")
          .and_return({ "attributes" => { "content" => "It is dark out." } })
        stub_camera("One person leaning in close.")
        expect(subject.index("Right now:")).to be < subject.index("Right now, your camera shows:")
      end

      it 'fails open when the fetch raises' do
        allow(HomeAssistantService).to receive(:entity).with("input_text.current_camera_state")
          .and_raise(StandardError, "HASS down")
        expect(Rails.logger).to receive(:warn).with(/Could not load input_text.current_camera_state/)
        expect { subject }.not_to raise_error
      end
    end

    context 'glitch premonition (imminent persona switch)' do
      def stub_next_switch(time)
        allow(Rails.cache).to receive(:read).and_call_original
        allow(Rails.cache).to receive(:read)
          .with(Recurring::Persona::RandomPersonaJob::NEXT_SWITCH_KEY)
          .and_return(time&.iso8601)
      end

      it 'injects the premonition when the next switch is within 3 minutes' do
        stub_next_switch(2.minutes.from_now)
        expect(subject).to include("You feel a glitch coming on")
      end

      it 'injects the premonition when the switch time has already passed (tick pending)' do
        stub_next_switch(1.minute.ago)
        expect(subject).to include("You feel a glitch coming on")
      end

      it 'injects nothing when the switch is further out' do
        stub_next_switch(20.minutes.from_now)
        expect(subject).not_to include("glitch coming on")
      end

      it 'injects nothing when no switch is scheduled' do
        stub_next_switch(nil)
        expect(subject).not_to include("glitch coming on")
      end

      it 'places the premonition LAST, below the camera view' do
        allow(HomeAssistantService).to receive(:entity).with("input_text.current_camera_state")
          .and_return({ "state" => "One person leaning in close." })
        stub_next_switch(1.minute.from_now)
        expect(subject.index("your camera shows")).to be < subject.index("You feel a glitch coming on")
      end

      it 'fails open when the cached timestamp is garbage' do
        allow(Rails.cache).to receive(:read).and_call_original
        allow(Rails.cache).to receive(:read)
          .with(Recurring::Persona::RandomPersonaJob::NEXT_SWITCH_KEY)
          .and_return("not a time")
        expect(Rails.logger).to receive(:warn).with(/Could not load glitch premonition/)
        expect { subject }.not_to raise_error
      end
    end

    context 'overall memory (the world board)' do
      it 'injects the latest overall summary, not truncated, in a structural layout' do
        create(:summary, summary_type: 'overall', summary_text: 'The whole night has been rowdy.',
               metadata: { durable_facts: 'Camp Trashy: possible fashion show tomorrow.',
                           recurring_visitors: 'Marco: wants a lavender-purple glow.',
                           active_threads: 'Laurie is back at midnight for a reading.',
                           director_note: 'Devices are failing across every stint.' }.to_json,
               created_at: 1.minute.ago)

        expect(subject).to include("## The bigger picture")
        expect(subject).to include("The whole night has been rowdy.")
        expect(subject).to include("## Durable places / camps / event facts")
        expect(subject).to include("Camp Trashy: possible fashion show tomorrow.")
        expect(subject).to include("## Recurring visitors")
        expect(subject).to include("Marco: wants a lavender-purple glow.")
        expect(subject).to include("## Still in the air")
        expect(subject).to include("Laurie is back at midnight for a reading.")
        expect(subject).to include("## A note to all of the cube's personas right now")
        expect(subject).to include("Devices are failing across every stint.")
      end

      it 'does not hard-truncate a long overall narrative' do
        long = "x" * 2000
        create(:summary, summary_type: 'overall', summary_text: long, created_at: 1.minute.ago)
        expect(subject).to include(long)
      end

      it 'orders the world-board sections narrative → facts → visitors → threads → director' do
        create(:summary, summary_type: 'overall', summary_text: 'A rowdy night.',
               metadata: { durable_facts: 'Camp Trashy.', recurring_visitors: 'Marco.',
                           active_threads: 'Laurie at midnight.', director_note: 'Lights lag.' }.to_json,
               created_at: 1.minute.ago)

        i_narrative = subject.index("The bigger picture")
        i_facts     = subject.index("Durable places")
        i_visitors  = subject.index("Recurring visitors")
        i_threads   = subject.index("Still in the air")
        i_director  = subject.index("A note to all of the cube's personas")
        expect([ i_narrative, i_facts, i_visitors, i_threads, i_director ]).to eq([ i_narrative, i_facts, i_visitors, i_threads, i_director ].sort)
      end
    end

    context "the cube's recent history (handoffs)" do
      let!(:zorp) { Persona.create!(slug: "zorp", name: "Zorp") }
      let!(:crash) { Persona.create!(slug: "crash", name: "Crash") }

      it 'injects the last two neutral handoff reports, persona-labeled' do
        create(:summary, summary_type: 'handoff', persona: crash, summary_text: 'Crash sparred with a rowdy crowd.',
               start_time: 40.minutes.ago, end_time: 20.minutes.ago, created_at: 20.minutes.ago)
        create(:summary, summary_type: 'handoff', persona: zorp, summary_text: 'Zorp read a few visitors.',
               start_time: 20.minutes.ago, end_time: 5.minutes.ago, created_at: 5.minutes.ago)

        expect(subject).to include("recent history")
        expect(subject).to include("Crash").and include("Crash sparred with a rowdy crowd.")
        expect(subject).to include("Zorp").and include("Zorp read a few visitors.")
      end
    end

    context 'persona memory' do
      let(:persona_slug) { "zorp" }
      let!(:zorp) { Persona.create!(slug: "zorp", name: "Zorp") }

      it 'injects the current persona summary and its self-steering note' do
        create(:summary, persona: zorp, summary_type: 'persona',
               summary_text: 'You did a lot of cosmic readings.',
               metadata: { ooc_note: 'Ease off the butt-readings.' }.to_json,
               created_at: 1.minute.ago)

        expect(subject).to include("What you (Zorp) remember")
        expect(subject).to include("You did a lot of cosmic readings.")
        expect(subject).to include("A note to yourself: Ease off the butt-readings.")
      end

      it 'injects nothing persona-specific when no persona is given' do
        create(:summary, persona: zorp, summary_type: 'persona', summary_text: 'zorp memory', created_at: 1.minute.ago)
        result = described_class.new(persona: nil).build
        expect(result).not_to include("remember from your recent time")
      end
    end

    context 'your current session (current-stint interaction chunks)' do
      let(:persona_slug) { "zorp" }
      let!(:zorp) { Persona.create!(slug: "zorp", name: "Zorp") }

      it "injects this persona's chunks since its last fold, and excludes already-folded ones" do
        # The fold's folded_through_at cursor is the boundary — chunks created at/before it are folded.
        fold = create(:summary, persona: zorp, summary_type: 'persona', summary_text: 'prior self',
                      created_at: 30.minutes.ago,
                      metadata: { folded_through_at: 34.minutes.ago.iso8601(6) }.to_json)
        create(:summary, persona: zorp, summary_type: 'interaction', summary_text: 'FOLDED chunk',
               start_time: 40.minutes.ago, end_time: 35.minutes.ago, created_at: 35.minutes.ago)
        create(:summary, persona: zorp, summary_type: 'interaction', summary_text: 'FRESH chunk',
               start_time: 10.minutes.ago, end_time: 5.minutes.ago, created_at: 5.minutes.ago)

        expect(fold).to be_present
        expect(subject).to include("Your current session so far")
        expect(subject).to include("FRESH chunk")
        expect(subject).not_to include("FOLDED chunk")
      end
    end

    it 'returns only the always-on event note when nothing else is available' do
      expect(subject).to eq(described_class::EVENT_NOTE)
    end

    context 'conversation pacing (wrap-it-up nudge)' do
      subject { described_class.new(persona: nil, conversation: conversation).build }
      let(:conversation) { create(:conversation) }

      def log_rounds(count)
        create_list(:conversation_log, count, conversation: conversation)
      end

      it 'injects nothing before the 5th round' do
        log_rounds(3) # building round 4
        expect(subject).not_to include("rounds into this conversation")
      end

      it 'nudges toward goal-or-wrap-up from the 5th round on' do
        log_rounds(4) # building round 5
        expect(subject).to include("You're 5 rounds into this conversation")
        expect(subject).to include("continue_conversation")
        expect(subject).to include('saying "Hey Glitch Cube"')
      end

      it 'keeps counting on later rounds' do
        log_rounds(7)
        expect(subject).to include("You're 8 rounds into this conversation")
      end

      it 'injects nothing when no conversation is given' do
        expect(described_class.new(persona: nil).build).not_to include("rounds into this conversation")
      end
    end
  end
end
