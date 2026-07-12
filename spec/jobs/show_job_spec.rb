# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShowJob, type: :job do
  it 'resolves the show class from its name and runs it with the given args' do
    show = instance_double(Shows::GrandEntrance, call: nil)
    allow(Shows::GrandEntrance).to receive(:new).with(persona: "jax").and_return(show)

    described_class.new.perform("grand_entrance", persona: "jax")

    expect(show).to have_received(:call)
  end

  it 'queues on the default queue' do
    expect(described_class.new.queue_name).to eq('default')
  end
end
