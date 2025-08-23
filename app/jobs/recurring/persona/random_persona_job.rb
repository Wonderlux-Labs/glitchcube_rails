# app/jobs/async_tool_job.rb
require "mission_control/jobs" if defined?(Rails)

module Recurring
  module Persona
    class RandomPersonaJob < ApplicationJob
  queue_as :default

  def perform
    if rand(1..100) > 20
      # do nothing
    else
      CubePersona.set_random
    end
  end
    end
  end
end
