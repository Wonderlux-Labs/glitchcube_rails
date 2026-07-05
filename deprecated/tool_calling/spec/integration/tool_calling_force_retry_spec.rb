require 'rails_helper'

RSpec.describe 'Forced Tool Calling Retry', type: :integration do
  let(:session_id) { "force-retry-#{SecureRandom.hex(4)}" }

  describe 'forcing retry with mocked validation errors' do
    it 'demonstrates full retry cycle with VCR', :vcr do
      # Mock Home Assistant
      allow(HomeAssistantService).to receive(:call_service).and_return({ "success" => true })
      allow(HomeAssistantService).to receive(:entity).and_return({
        "state" => "off",
        "attributes" => { "supported_features" => 63 }
      })

      # Force get_light_state to fail on first attempt via Tools::Registry (sync tool)
      call_count = 0
      original_execute = Tools::Registry.method(:execute_tool)
      allow(Tools::Registry).to receive(:execute_tool) do |tool_name, **args|
        if tool_name == "get_light_state"
          call_count += 1

          if call_count == 1
            # First call - force validation error only if entity is actually invalid
            if [ "light.cube_voice_ring", "light.cube_light_top", "light.cube_inner" ].include?(args[:entity_id])
              # If LLM chose a valid entity, we'll force a different kind of error
              {
                success: false,
                error: "Light #{args[:entity_id]} is currently unreachable",
                details: [ "Network timeout", "Please try a different light" ]
              }
            else
              # If LLM chose an invalid entity, give proper validation error
              {
                success: false,
                error: "Entity '#{args[:entity_id]}' is not a cube light",
                available_lights: [ "light.cube_voice_ring", "light.cube_light_top", "light.cube_inner" ]
              }
            end
          else
            # Second call - succeed with valid entity
            {
              success: true,
              state: "on",
              brightness: 75,
              rgb_color: [ 255, 255, 255 ],
              entity_id: args[:entity_id]
            }
          end
        else
          # Other tools use original behavior
          original_execute.call(tool_name, **args)
        end
      end

      service = ToolCallingService.new(session_id: session_id)

      # Use a request that should trigger get_light_state (sync tool)
      intent = "Check the status of light.invalid_entity"
      context = { persona: "jax" }

      result = service.execute_intent(intent, context)

      # Should get a successful response after retry
      expect(result).to be_a(String)
      expect(result).not_to eq("I'm having trouble with that right now.")

      # Should have retried: the first call fails, a later call succeeds. The
      # exact count depends on how many times the live model re-invokes the
      # tool, so assert the retry happened (>1) rather than a brittle exact count.
      expect(call_count).to be > 1
    end
  end
end
