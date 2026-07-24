# app/services/tools/music/play_music.rb
#
# The one way to play music on the jukebox — for both front-and-center songs and quiet
# background music; the required volume decides which. Wraps script.play_music_on_jukebox.
class Tools::Music::PlayMusic < Tools::BaseTool
  def self.definition
    @definition ||= begin
      tool = OpenRouter::Tool.define do
        name "play_music"
        description "Play music on the cube's jukebox — for BOTH front-and-center songs and " \
                    "quiet background music; the required volume decides which. query is a fuzzy " \
                    "search: give 'Artist - Title' (e.g. 'Nirvana - Smells Like Teen Spirit') or " \
                    "'Artist - Album - Title'. volume is REQUIRED (25-35 = background under the " \
                    "conversation, 80-90 = front-and-center / dance party). queue is optional: " \
                    "replace (default) plays now, replace_next queues it as the next track."
        parameters do
          string :query, required: true, description: "Fuzzy track search, e.g. 'Artist - Title'."
          number :volume, required: true, minimum: 0, maximum: 100,
                 description: "REQUIRED. 25-35 = quiet background, 80-90 = front-and-center."
          string :queue, description: "replace (default, play now) or replace_next (queue as next track).",
                 enum: %w[replace replace_next]
        end
      end

      def tool.validation_blocks
        @validation_blocks ||= [
          proc do |params, errors|
            params = params.transform_keys(&:to_s)

            errors << "query is required." if params["query"].blank?

            if params["volume"].blank?
              errors << "volume is required — 25-35 for background, 80-90 for front-and-center."
            elsif !(0..100).cover?(params["volume"].to_i)
              errors << "volume must be between 0 and 100. Got: #{params["volume"]}."
            end

            nil # mutate `errors`; don't return an array (ValidatedToolCall would re-append it)
          end
        ]
      end

      tool
    end
  end

  def call(query:, volume:, queue: nil)
    return error_response("query is required.") if query.blank?
    return error_response("volume is required (0-100).") if volume.blank?

    vars = { query: query, volume: volume.to_i }
    vars[:queue] = queue if queue.present?

    service_call = run_script("play_music_on_jukebox", **vars)
    success_response("Playing '#{query}' at volume #{volume}", service_calls: [ service_call ])
  end
end
