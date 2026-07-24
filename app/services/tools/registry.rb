# app/services/tools/registry.rb
#
# The in-Rails tool registry. Groups the environment tools into the two translator
# LANES that ActionExecutor dispatches in parallel:
#   :action — lights, marquee, persona, announcements
#   :sound  — the jukebox (music + sound effects)
# ToolCallingService asks this for a lane's tool definitions (what the translator LLM
# may call), then looks each returned call back up by name and executes it. All personas
# currently share the same tools — lane, not persona, is the selection axis.
class Tools::Registry
  LANES = {
    action: [
      Tools::Lights::SetLight,
      Tools::Lights::DanceMode,
      Tools::Lights::JazzMode,
      Tools::Display::Marquee,
      Tools::Display::ClearMarquee,
      Tools::Modes::SetPersona,
      Tools::Communication::Announcement
    ].freeze,
    sound: [
      Tools::Music::PlayMusic,
      Tools::Music::PlaySoundEffect
    ].freeze
  }.freeze

  class << self
    # Tool classes for a lane (:action / :sound).
    def tools_for_lane(lane)
      LANES.fetch(lane.to_sym, [])
    end

    # OpenRouter tool definitions for a lane (what the translator LLM sees).
    def tool_definitions_for_lane(lane)
      tools_for_lane(lane).map(&:definition)
    end

    # name => tool class, across all lanes.
    def all_tools
      @all_tools ||= LANES.values.flatten.index_by { |klass| klass.definition.name }
    end

    def get_tool(name)
      all_tools[name.to_s]
    end

    # The OpenRouter::Tool definition for a name (used to validate a tool call).
    def definition_for(name)
      get_tool(name)&.definition
    end

    # Execute a tool by name. Filters blank args (the translator often includes empty
    # optionals) and symbolizes keys for the Ruby keyword call.
    def execute_tool(name, **args)
      tool_class = get_tool(name)
      return { success: false, error: "Tool '#{name}' not found" } unless tool_class

      symbol_args = args.reject { |_k, v| v.blank? }
                        .transform_keys { |k| k.is_a?(String) ? k.to_sym : k }
      tool_class.call(**symbol_args)
    end
  end
end
