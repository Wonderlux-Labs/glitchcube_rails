# app/services/tools/music/play_music.rb
class Tools::Music::PlayMusic < Tools::BaseTool
  def self.description
    "Play specific music tracks on the Cube's sound system via Music Assistant"
  end

  def self.narrative_desc
    "control music - play specific tracks on the sound system - we have fuzzy search just send in your best guess, you can also queue it up, play it next or play it now!"
  end

  def self.prompt_schema
    "play_music(artist: 'Pink Floyd', album: 'Dark Side of the Moon') - Play music on the Cube's sound system"
  end

  def self.tool_type
    :async # Music control happens after response
  end

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "play_music"
      description "Play music on the Cube's jukebox with fuzzy search - can search by song, artist, or any combination"

      parameters do
        string :media_id, required: true,
               description: "REQUIRED: The song you want to play - fuzzy search works, so can do 'Watermelon Man by Herbie Hancock' or 'Nirvana - Teen Spirit'. The more precise the better."

        string :artist,
               description: "Optional: Artist name to narrow down search results if getting funny results"

        string :album,
               description: "Optional: Album name to further narrow down search if needed"

        string :enqueue,
               description: "Queue mode: 'play' (force play now), 'replace' (replace queue and play), 'next' (add after current), 'replace_next' (default), 'add' (end of queue)",
               enum: [ "play", "replace", "next", "replace_next", "add" ]
      end
    end
  end

  def call(media_id:, artist: nil, album: nil, enqueue: "replace_next")
    # Build service data for the script call (script expects parameters directly, not wrapped in variables)
    service_data = {
      media_id: media_id,
      enqueue: enqueue
    }

    # Add optional parameters
    service_data[:artist] = artist if artist.present?
    service_data[:album] = album if album.present?

    # Call the Home Assistant script
    begin
      result = HomeAssistantService.call_service("script", "play_music_on_jukebox", service_data)

      response_message = "Playing: \"#{media_id}\""
      response_message += " by #{artist}" if artist
      response_message += " from #{album}" if album
      response_message += " (#{enqueue} mode)" if enqueue != "replace_next"

      success_response(
        response_message,
        script: "play_music_on_jukebox",
        media_id: media_id,
        artist: artist,
        album: album,
        enqueue: enqueue,
        service_result: result
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to play music: #{e.message}")
    end
  end
end
